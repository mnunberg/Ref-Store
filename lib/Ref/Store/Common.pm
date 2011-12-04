package Ref::Store::Common;
use strict;
use warnings;
our @EXPORT;
use base qw(Exporter);
use Log::Fu { level => "debug" };

BEGIN {
    my $i = 0;
    foreach (qw(STRSCALAR REFSCALAR TABLEREF)) {
        my $v = $i;
        $i++;
        {
            no strict 'refs';
            my $fname = "HR_KFLD_$_";
            #log_debug("$fname=$v");
            *{$fname} = sub () { $v };
            push @EXPORT, $fname;
        }
    }
    {
        no strict 'refs';
        $i++;
        *{HR_KFLD_AVAILABLE} = sub () { $i };
        push @EXPORT, 'HR_KFLD_AVAILABLE';
        
        *{HR_REVERSE_KEYS} = sub () { 0 };
        *{HR_REVERSE_ATTRS} = sub () { 1 };
        
        push @EXPORT, map { 'HR_REVERSE_'.$_ } qw(KEYS ATTRS);
    }
}


1;