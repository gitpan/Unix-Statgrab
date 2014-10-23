package Config::AutoConf::SG;

use strict;
use warnings;

use parent qw(Config::AutoConf);
use Capture::Tiny qw/capture/;
use Text::ParseWords qw(shellwords);

sub new
{
    my ( $class, %args ) = @_;
    my $self = $class->SUPER::new(%args);
    # XXX might add c++ if required for some operating systems
    return $self;
}

sub check_prog_pkg_config
{
    my $self = shift->_get_instance();
    defined $self->{cache}->{ac_cv_proc_pkg_config}
      or $self->{cache}->{ac_cv_proc_pkg_config} = $self->check_prog("pkg-config");
    return $self->{cache}->{ac_cv_proc_pkg_config};
}

sub pkg_config_flags
{
    my ( $self, $package, $lib, $header, $func ) = @_;
    $self = $self->_get_instance();
    my $cache_name = $self->_cache_name( "lib", $lib, $func );
    defined $self->{cache}->{$cache_name} or do
    {
        my $pkg_config = $self->check_prog_pkg_config;
        my ( $stdout, $stderr, $exit );

        # do not separate between libs and extra (for now) - they come with -l prepended
        ( $stdout, $stderr, $exit ) =
          capture { system( $pkg_config, $package, "--libs" ); };
        chomp $stdout;
        0 == $exit
          and $self->{cache}->{$cache_name} = [
            map {
                $_ =~ s/^\s+//;
                $_ =~ s/\s+$//;
                Text::ParseWords::shellwords $_;
              } split( m/\n/, $stdout )
          ]
          and push @{ $self->{extra_link_flags} }, @{ $self->{cache}->{$cache_name} };

        $cache_name = $self->_cache_name($header);
        ( $stdout, $stderr, $exit ) =
          capture { system( $pkg_config, $package, "--cflags" ); };
        chomp $stdout;
        0 == $exit
          and $self->{cache}->{$cache_name} = [
            map {
                $_ =~ s/^\s+//;
                $_ =~ s/\s+$//;
                Text::ParseWords::shellwords $_;
              } split( m/\n/, $stdout )
          ]
          and push @{ $self->{extra_compile_flags}->{ $self->{lang} } },
          @{ $self->{cache}->{$cache_name} };
    };
}

sub check_libstatgrab
{
    my ($self) = @_;
    ref($self) or $self = $self->_get_instance();
    $self->pkg_config_flags( "libstatgrab", "statgrab", "statgrab.h", "sg_get_process_stats_r" );

    return $self->search_libs( "sg_get_process_stats_r", ["statgrab"] );
}

sub _default_headers_with_perl
{
    my ($self) = @_;

    my $include_perl = "#include <EXTERN.h>\n#include <perl.h>";
    my $includes = join( "\n", $self->_default_includes, $include_perl );

    return $includes;
}

my %TYPE_ASSO = (
                  UV => "unsigned long long",
                  IV => "long long"
                );

sub _check_sizeof_type_fit_stat
{
    my ( $self, $type ) = @_;

    my $includes    = $self->_default_headers_with_perl();
    my $match_check = "sizeof($type) == sizeof($TYPE_ASSO{$type})";
    my $conftest    = $self->lang_build_bool_test( $includes, $match_check );

    my $match_size = $self->compile_if_else($conftest);

    return $match_size;
}

sub _match_type_define_name
{
    my $type            = $_[0];
    my $match_name      = "MATCH_" . uc($type) . "_FIT_";
    my @type_asso_words = split( " ", $TYPE_ASSO{$type} );
    foreach my $taw (@type_asso_words) { $match_name .= uc( substr( $taw, 0, 1 ) ) }
    return $match_name;
}

sub check_sizeof_IVUV_fit_stat
{
    my ($self) = @_;

    my $match = 1;
    foreach my $type (qw(IV UV))
    {
        my $cache_size_match_name = $self->_cache_name( "type", $type, qw(size match ll) );
        my $check_size_match_sub = sub {
            my $match_size = $self->_check_sizeof_type_fit_stat($type);
            $self->define_var( _match_type_define_name($type),
                               $match_size ? $match_size : undef,
                               "defined when $type can hold any $TYPE_ASSO{$type} value" );

            return $match_size;
        };

        $match &=
          $self->check_cached( $cache_size_match_name,
                               "if $type can hold any $TYPE_ASSO{$type} value",
                               $check_size_match_sub );
    }

    return $match;
}

1;
