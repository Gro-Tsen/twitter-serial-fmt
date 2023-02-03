#! /usr/local/bin/perl -w

use strict;
use warnings;

my $f;
if ( defined($ARGV[0]) ) {
    open $f, "<", $ARGV[0] or die "Can't open $ARGV[0]: $!";
} else {
    $f = \*STDIN;
}

binmode STDOUT, ":utf8";

my $indent = 0;

sub outputbyte {
    my $v = shift;
    print ((" "x$indent) . "BYTE($v)\n");
}

sub outputint {
    my $v = shift;
    print ((" "x$indent) . "INT($v)\n");
}

sub outputlong {
    my $v = shift;
    print ((" "x$indent) . "LONG($v)\n");
}

sub outputfloat {
    my $v = shift;
    print ((" "x$indent) . "FLOAT($v)\n");
}

sub outputdouble {
    my $v = shift;
    print ((" "x$indent) . "DOUBLE($v)\n");
}

sub outputboolean {
    my $v = shift;
    $v = ($v ? "True" : "False");
    print ((" "x$indent) . "BOOLEAN($v)\n");
}

sub outputnull {
    print ((" "x$indent) . "NULL\n");
}

sub outputstartobj {
    my $v = shift;
    print ((" "x$indent) . "STARTOBJ($v)\n");
    $indent += 2;
}

sub outputendobj {
    $indent = ($indent>=2 ? $indent-2 : 0);
    print ((" "x$indent) . "ENDOBJ\n");
}

sub outputstring {
    my $str = shift;
    my $unicode = shift;
    my $quotedstr = $str;
    $quotedstr =~ s/([\"\\])/\\$1/g;
    $quotedstr =~ s/\n/\\n/g;
    $quotedstr =~ s/\t/\\t/g;
    $quotedstr = ($unicode?"U":"") . "\"" . $quotedstr . "\"";
    print ((" "x$indent) . "STRING($quotedstr)\n");
}

sub outputtype16 {
    my $v = shift;
    print ((" "x$indent) . "UNKNOWNTYPE16($v)\n");
}

sub readintval {
    my $cnt = shift;
    my $buf;
    my $ret = read($f, $buf, $cnt);
    die "Read error: $!" unless defined($ret);
    die "Premature EOF" unless $ret == $cnt;
    if ( $cnt == 1 ) {
	return unpack("C", $buf);
    } elsif ( $cnt == 2 ) {
	return unpack("S>", $buf);
    } elsif ( $cnt == 4 ) {
	return unpack("L>", $buf);
    } elsif ( $cnt == 8 ) {
	return unpack("Q>", $buf);
    } else {
	die "This shouldn't happen";
    }
}

sub readfloatval {
    my $cnt = 4;
    my $buf;
    my $ret = read($f, $buf, $cnt);
    die "Read error: $!" unless defined($ret);
    die "Premature EOF" unless $ret == $cnt;
    return unpack("f>", $buf);
}

sub readdoubleval {
    my $cnt = 8;
    my $buf;
    my $ret = read($f, $buf, $cnt);
    die "Read error: $!" unless defined($ret);
    die "Premature EOF" unless $ret == $cnt;
    return unpack("d>", $buf);
}

sub readchar {
    my $ch;
    my $ret = read($f, $ch, 1);
    die "Read error: $!" unless defined($ret);
    die "Premature EOF" unless $ret == 1;
    return $ch;
}

sub readstring {
    my $len = shift;
    my $buf;
    while ( $len ) {
	$buf .= readchar;
	$len--;
    }
    return $buf;
}

sub readutf8string {
    my $len = shift;
    my $buf;
    while ( $len ) {
	my $ch = readchar;
	my $ord = ord($ch);
	if ( $ord<0x80 ) {
	    $buf .= $ch;
	} elsif ( $ord>=0xc0 && $ord<0xe0 ) {
	    my $ord2 = ord(readchar);
	    $buf .= chr(($ord&0x1f)<<6 | ($ord2&0x3f));
	} elsif ( $ord>=0xe0 && $ord<0xf0 ) {
	    my $ord2 = ord(readchar);
	    my $ord3 = ord(readchar);
	    $buf .= chr(($ord&0x1f)<<12 | ($ord2&0x3f)<<6 | ($ord3&0x3f));
	} elsif ( $ord>=0xf0 && $ord<0xf8 ) {
	    my $ord2 = ord(readchar);
	    my $ord3 = ord(readchar);
	    my $ord4 = ord(readchar);
	    $buf .= chr(($ord&0x1f)<<18 | ($ord2&0x3f)<<12 | ($ord3&0x3f)<<6 | ($ord4&0x3f));
	    $len--;
	    die "Tried to split a surrogate" if $len<=0;
	}
	$len--;
    }
    return $buf;
}

while (1) {
    my $ch;
    my $ret = read($f, $ch, 1);
    die "Read error: $!" unless defined($ret);
    last unless $ret;
    my $byte = unpack("C", $ch);
    my $type = $byte>>3;
    my $subtype = $byte&0x07;
    # my $hexbyte = sprintf("0x%02x", $byte);
    # print STDERR "DEBUG: byte=$byte=$hexbyte, type=$type, subtype=$subtype\n";
    if ( $type == 1 ) { # byte
	if ( $subtype == 0 ) {
	    my $v = readintval(1);
	    outputbyte($v);
	} elsif ( $subtype == 1 ) {
	    outputbyte(0);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 2 ) { # int
	if ( $subtype == 0 ) {
	    my $v = readintval(4);
	    outputint($v);
	} elsif ( $subtype == 1 ) {
	    outputint(0);
	} elsif ( $subtype == 2 ) {
	    my $v = readintval(1);
	    outputint($v);
	} elsif ( $subtype == 3 ) {
	    my $v = readintval(2);
	    outputint($v);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 3 ) { # long
	if ( $subtype == 0 ) {
	    my $v = readintval(4);  # This makes no sense :-(
	    outputlong($v);
	} elsif ( $subtype == 1 ) {
	    outputlong(0);
	} elsif ( $subtype == 2 ) {
	    my $v = readintval(1);
	    outputlong($v);
	} elsif ( $subtype == 3 ) {
	    my $v = readintval(2);
	    outputlong($v);
	} elsif ( $subtype == 5 ) {
	    my $v = readintval(8);
	    outputlong($v);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 4 ) { # float
	if ( $subtype == 0 ) {
	    my $v = readfloatval();
	    outputfloat($v);
	} elsif ( $subtype == 1 ) {
	    outputfloat(0);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 5 ) { # double
	if ( $subtype == 0 ) {
	    my $v = readdoubleval();
	    outputdouble($v);
	} elsif ( $subtype == 1 ) {
	    outputdouble(0);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 6 ) { # boolean
	if ( $subtype == 0 ) {
	    outputboolean(0);
	} elsif ( $subtype == 1 ) {
	    outputboolean(1);  # How illogical!
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 7 ) { # null
	if ( $subtype == 0 ) {
	    outputnull;
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 8 ) { # string_utf8
	if ( $subtype == 1 ) {
	    outputstring("", 1);
	} elsif ( $subtype == 2 ) {
	    my $v = readintval(1);
	    # print STDERR "DEBUG: about to read UTF-8 string of length $v\n";
	    my $str = readutf8string($v);
	    outputstring($str, 1);
	} elsif ( $subtype == 3 ) {
	    my $v = readintval(2);
	    # print STDERR "DEBUG: about to read UTF-8 string of length $v\n";
	    my $str = readutf8string($v);
	    outputstring($str, 1);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 9 ) { # start_object
	if ( $subtype == 1 ) {
	    outputstartobj("ver=0");
	} elsif ( $subtype == 2 ) {
	    my $v = readintval(1);
	    outputstartobj("ver=$v");
	} elsif ( $subtype == 5 ) {
	    outputstartobj("tuple");
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 11 ) { # end_object
	if ( $subtype == 0 ) {
	    outputendobj(0);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 13 ) { # string_ascii
	if ( $subtype == 1 ) {
	    outputstring("");
	} elsif ( $subtype == 2 ) {
	    my $v = readintval(1);
	    # print STDERR "DEBUG: about to read string of length $v\n";
	    my $str = readstring($v);
	    outputstring($str);
	} elsif ( $subtype == 3 ) {
	    my $v = readintval(2);
	    # print STDERR "DEBUG: about to read string of length $v\n";
	    my $str = readstring($v);
	    outputstring($str);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } elsif ( $type == 16 ) { # type16
	if ( $subtype == 2 ) {
	    my $v = readintval(1);
	    outputtype16($v);
	} elsif ( $subtype == 3 ) {
	    my $v = readintval(2);
	    outputtype16($v);
	} else {
	    die "Don't know how to handle this: $byte";
	}
    } else {
	die "Don't know how to handle this: $byte";
    }
}
