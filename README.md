This is about the “serial” format used by Twitter: it was [announced
here](https://blog.twitter.com/engineering/en_us/topics/open-source/2017/introducing-serial)
in 2017 and the serializer source code [is
here](https://github.com/twitter/serial).

The Twitter Android app stores its data for cached tweets in this
format: the SQLite database
`/data/data/com.twitter.android/databases/$user_id-65-versioncode-$number.db`
contains the following `statuses` table, in which we are mainly
concerned with the `content` field:

```
CREATE TABLE statuses (
	_id INTEGER PRIMARY KEY,
	status_id INTEGER UNIQUE NOT NULL,
	author_id INTEGER,
	content BLOB /*NULLABLE*/,
	created INTEGER,
	in_r_user_id INTEGER,
	in_r_status_id INTEGER,
	in_r_screen_name TEXT /*NULLABLE*/,
	favorited INTEGER,
	retweeted INTEGER,
	favorite_count INTEGER,
	retweet_count INTEGER,
	quote_count INTEGER NOT NULL DEFAULT 0,
	view_count INTEGER,
	view_count_info BLOB /*NULLABLE*/,
	flags INTEGER,
	latitude TEXT /*NULLABLE*/,
	longitude TEXT /*NULLABLE*/,
	place_data BLOB /*NULLABLE*/,
	card BLOB /*NULLABLE*/,
	lang TEXT /*NULLABLE*/,
	supplemental_language TEXT /*NULLABLE*/,
	quoted_tweet_id INTEGER,
	reply_count INTEGER,
	conversation_id INTEGER,
	r_ent_content BLOB /*NULLABLE*/,
	self_thread_id INTEGER,
	withheld_info BLOB /*NULLABLE*/,
	unified_card BLOB /*NULLABLE*/,
	is_reported INTEGER DEFAULT 0,
	composer_source TEXT /*NULLABLE*/,
	tweet_source TEXT /*NULLABLE*/,
	quoted_status_permalink BLOB /*NULLABLE*/,
	limited_actions TEXT /*NULLABLE*/,
	conversation_control BLOB /*NULLABLE*/,
	has_birdwatch_notes INTEGER,
	voice_info BLOB /*NULLABLE*/,
	birdwatch_pivot BLOB /*NULLABLE*/,
	super_follows_conversation_user_screen_name TEXT /*NULLABLE*/,
	exclusive_tweet_creator_screen_name TEXT /*NULLABLE*/,
	community_id INTEGER,
	community BLOB /*NULLABLE*/,
	tweet_community_relationship BLOB /*NULLABLE*/,
	quick_promote_eligibility BLOB /*NULLABLE*/,
	unmention_info BLOB /*NULLABLE*/,
	trusted_friends_creator_screen_name TEXT /*NULLABLE*/,
	collaborators BLOB /*NULLABLE*/,
	vibe BLOB /*NULLABLE*/,
	edit_control BLOB /*NULLABLE*/,
	previous_counts BLOB /*NULLABLE*/,
	tweet_conversation_context BLOB /*NULLABLE*/,
	tweet_limited_action_results BLOB /*NULLABLE*/,
	tweet_edit_perspective BLOB /*NULLABLE*/,
	note_tweet BLOB /*NULLABLE*/
);
```

But the same format is also used, e.g., in the `card` field of the
same table and the `description` field of the `users` table.

Various examples are shown in [this
dump](https://gist.github.com/Gro-Tsen/aafb9ae03978044ea3d782a38e0e3af6)
(along with their JSON counterpart, the original being from [this
Twitter
thread](https://twitter.com/tsen_gro/status/1621490666957160450)), as
well as [this Twitter
thread](https://twitter.com/gro_tsen/status/1621455828271206401).

* Each object begins with a header byte.  The top 5 bits are the type
  and the bottom 3 bits are subtype.
  - Types are as follows ([source
  here](https://github.com/twitter/Serial/blob/master/serialization/src/main/java/com/twitter/serial/stream/SerializerDefs.java#L22)):
    0=unknown, 1=byte, 2=int, 3=long, 4=float, 5=double, 6=boolean,
    7=null, 8=string\_utf8, 9=start\_object, 10=start\_object\_debug,
    11=end\_object, 12=eof, 13=string\_ascii, 14=byte\_array.
  - Subtypes as are follows ([source here](https://github.com/twitter/Serial/blob/master/serialization/src/main/java/com/twitter/serial/stream/bytebuffer/ByteBufferSerializerDefs.java#L32)):
    0=undefined, 1=default, 2=byte, 3=short, 4=int, 5=long.
    Subtype indicates the size of the following value (integer proper
    or string length) as follows: 0→type-dependent, 1→0, 2→1, 3→2,
    4→4, 5→8.

* Header byte is followed by a value whose size is indicated by the
  subtype of the header byte (see above), generally understood as 0
  for subtype “default” (see next item), and which is interpreted as
  follows:
  - The value itself for a scalar (integer or float) type.  If shorter
    than the type, it is zero-extended.
  - The length of the string for a string.  In the case of
    string\_utf8 this is the number of Java chars, i.e. UTF-16
    sedecuplets (*not* the number of UTF-8 octets *nor* the number of
    Unicode codepoints, *sigh*).
  - The length of the byte array for a byte array (in bytes).
  - The version number for an object (whatever that means).

* The subtypes “default” and “undefined” are understood as follows:
  - byte: “default” means 0, “undefined” means a value of length 1
    follows.
  - int: “default” means 0, “undefined” means a value of length 4
    follows.
  - long: “default” means 0, “undefined” means a value of length 4
    follows (for length 8, use “long” subtype).
  - float: “default” means 0, “undefined” means a value of length 8
    follows.
  - boolean: “default” means true, “undefined” means false, and there
    never is any following value (*sigh*, this is highly illogical).
  - strings: “default” means empty string.
  - byte\_array: “default” should mean empty array, but the serializer
    appears to emit “undefined” subtype, which seems to conflict with
    what the unserializer expects (*sigh*).

* Common examples:
  - 0x08 means (type=1=byte, subtype=0=undefined) header byte will be
    followed by one value byte giving the actual byte.
  - 0x09 means (type=1=byte, subtype=1=default) the byte 0.
  - 0x11 means (type=2=int, subtype=1=default) the integer 0.
  - 0x12 means (type=2=int, subtype=2=byte) header byte will be
    followed by one value byte giving the actual integer
    (zero-extended).
  - 0x42 means (type=13=string\_utf8, subtype=2=byte) header byte will
    be followed by one length byte and then by the actual string
    having that length in UTF-16 sedecuplets.
  - 0x49 means (type=9=start\_object, subtype=1=default) start of
    object with version number zero.
  - 0x58 means (type=11=end\_object, subtype=0=undefined) end of
    object.
  - 0x69 means (type=13=string\_ascii, subtype=1=default) the empty
    string.
  - 0x6a means (type=13=string\_ascii, subtype=2=byte) header byte
    will be followed by one length byte and then by the actual string
    having that length.

* More mysterious:
  - 0x4d (type=9=start\_object, subtype=5=long?) seems to be a start
    of object (array, maybe?).
  - 0x82 (type=17=???, subtype=2=byte) seems to be followed by a single
    byte.  Meaning unclear.

Note that HTML/XML special chars are **not** ampersand-escaped.
