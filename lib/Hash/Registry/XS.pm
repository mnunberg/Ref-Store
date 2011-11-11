package Hash::Registry::XS::cfunc;
use strict;
use warnings;
use File::Slurp qw(read_file);
use Dir::Self;
use base qw(Exporter);

my $CBLOB;
BEGIN {
    my $base_path = "/home/mordy/src/Hash-Registry/";
    my @filenames = qw(
        hreg.h
        hreg.c
        hr_hrimpl.c
        hr_pl.c
    );
    foreach my $file (@filenames) {
        $CBLOB .= sprintf("\n/* FILE: %s */\n", $file);
        $CBLOB .= read_file("$base_path/$file");
    }
    $CBLOB =~ s/^#include.+hreg\.h[">\s+]$//mgi;
}


use Inline
    C => Config =>
    NAME => 'hreg',
    CLEAN_AFTER_BUILD => 0,
    DIRECTORY   => './inline_build',
    #FORCE_BUILD => 1,
    BUILD_NOISY => 1
;
use Inline C => $CBLOB;

our @EXPORT = qw(
    HR_PL_add_actions
    HR_PL_del_action
    
    HR_impl_value_init
    HR_impl_key_init
    HR_impl_value_init_a
);

package Hash::Registry::XS::Key;
use strict;
use warnings;
use Scalar::Util qw(refaddr weaken);
use Devel::Peek;
use Data::Hexdumper qw(hexdump);
use Internals qw(SetRefCount GetRefCount);
use Hash::Registry::Common;
use base qw(Hash::Registry::Key);
Hash::Registry::XS::cfunc->import();
use Log::Fu;

sub new {
    my ($cls,$scalar,$table) = @_;
    my $self = [ "$scalar", $scalar, $table ];
    bless $self, $cls;
        
    HR_impl_key_init(
        $self, $table->forward, $table->scalar_lookup,
        "$scalar"
    );
    
    $table->scalar_lookup->{$scalar} = $self;
    weaken($table->scalar_lookup->{$scalar});
    
    return $self;
}

package Hash::Registry::XS;
use Scalar::Util qw(refaddr weaken);
use strict;
use warnings;
use base qw(Hash::Registry);
Hash::Registry::XS::cfunc->import();

sub kcls () { 'Hash::Registry::XS::Key' }
sub acls () { 'Hash::Registry::XS::Attribute' }

sub value_init {
    #my ($self,$value) = @_;
    HR_impl_value_init($_[1], $_[0]->reverse);
}

sub value_init_a {
    HR_impl_value_init_a($_[1], $_[2]);
}

sub value_cleanup {
    #my ($self,$value) = @_;
    HR_PL_del_action($_[1], $_[0]->reverse);
}

sub value_deinit_a {
    #my ($value,$attrhash) = @_;
    HR_PL_del_action($_[1], $_[2]);
}

sub impl_init { }

sub KString {
    my ($cls,$key) = @_;
    0+$key;
}