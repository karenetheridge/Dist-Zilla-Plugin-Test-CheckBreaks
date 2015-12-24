use strict;
use warnings;
package Dist::Zilla::Plugin::Test::CheckBreaks;
# ABSTRACT: Generate a test that shows what modules you are breaking
# KEYWORDS: distribution prerequisites upstream dependencies modules conflicts breaks breakages metadata
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.015';

use Moose;
with (
    'Dist::Zilla::Role::FileGatherer',
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::TextTemplate',
    'Dist::Zilla::Role::PrereqSource',
    'Dist::Zilla::Role::ModuleMetadata',
);
use Path::Tiny;
use Module::Runtime 'module_notional_filename';
use List::Util 1.33 qw(any first);
use Sub::Exporter::ForMethods 'method_installer';
use Data::Section 0.004 { installer => method_installer }, '-setup';
use Data::Dumper ();
use namespace::autoclean;

has no_forced_deps => (
    is => 'ro', isa => 'Bool',
    default => 0,
);

sub filename { path('t', 'zzz-check-breaks.t') }

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        conflicts_module => $self->conflicts_module,
        no_forced_deps => ($self->no_forced_deps ? 1 : 0),
        blessed($self) ne __PACKAGE__ ? ( version => $VERSION ) : (),
    };

    return $config;
};

sub gather_files
{
    my $self = shift;

    require Dist::Zilla::File::InMemory;

    $self->add_file( Dist::Zilla::File::InMemory->new(
        name => $self->filename->stringify,
        content => ${$self->section_data('test-check-breaks')},
    ));
}

has conflicts_module => (
    is => 'ro', isa => 'Str|Undef',
    lazy => 1,
    default => sub {
        my $self = shift;

        $self->log_debug('no conflicts_module provided; looking for one in the dist...');

        my $mmd = $self->module_metadata_for_file($self->zilla->main_module);
        my $module = ($mmd->packages_inside)[0] . '::Conflicts';

        # check that the file exists in the dist (it should never be shipped
        # separately!)
        my $conflicts_filename = module_notional_filename($module);
        if (any { $_->name eq path('lib', $conflicts_filename) } @{ $self->zilla->files })
        {
            $self->log_debug([ '%s found', $module ]);
            return $module;
        }

        $self->log_debug([ 'No %s found', $module ]);
        return undef;
    },
);

sub _cmc_prereq { '0.011' }

sub munge_files
{
    my $self = shift;

    my $breaks_data = $self->_x_breaks_data;
    $self->log_debug('no x_breaks metadata and no conflicts module found to check against: adding no-op test')
        if not keys %$breaks_data and not $self->conflicts_module;

    my $filename = $self->filename;
    my $file = first { $_->name eq $filename } @{ $self->zilla->files };

    my $content = $self->fill_in_string(
        $file->content,
        {
            dist => \($self->zilla),
            plugin => \$self,
            module => \($self->conflicts_module),
            no_forced_deps => \($self->no_forced_deps),
            breaks => \$breaks_data,
            cmc_prereq => \($self->_cmc_prereq),
            test_count => \($self->_test_count),
        }
    );

    $content =~ s/\n\n\z/\n/;
    $file->content($content);

    return;
}

sub register_prereqs
{
    my $self = shift;

    $self->zilla->register_prereqs(
        {
            phase => 'test',
            type  => 'requires',
        },
        'Test::More' => '0',
    );

    return if not keys %{ $self->_x_breaks_data };

    $self->zilla->register_prereqs(
        {
            phase => 'test',
            type  => $self->no_forced_deps ? 'suggests' : 'requires',
        },
        'CPAN::Meta::Requirements' => '0',
        'CPAN::Meta::Check' => $self->_cmc_prereq,
    );
}

has _x_breaks_data => (
    is => 'ro', isa => 'HashRef[Str]',
    init_arg => undef,
    lazy => 1,
    default => sub {
        my $self = shift;
        my $breaks_data = $self->zilla->distmeta->{x_breaks};
        defined $breaks_data ? $breaks_data : {};
    },
);

sub _test_count {
    my $self = shift;

    my $test_count = 1; # 1 for conflicts module, always
    ++$test_count if not keys %{ $self->_x_breaks_data };
    return $test_count;
}

__PACKAGE__->meta->make_immutable;

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    [Breaks]
    Foo = <= 1.1    ; Foo at 1.1 or lower will break when I am installed

    [Test::CheckBreaks]
    conflicts_module = Moose::Conflicts

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that runs at the
L<gather files|Dist::Zilla::Role::FileGatherer> stage, providing a test file
that runs last in your test suite and checks for conflicting modules, as
indicated by C<x_breaks> in your distribution metadata.
(See the F<t/zzz-check-breaks.t> test in this distribution for an example.)

C<x_breaks> entries are expected to be
L<version ranges|CPAN::Meta::Spec/Version Ranges>, with one
addition, for backwards compatibility with
L<[Conflicts]|Dist::Zilla::Plugin::Conflicts>: if a bare version number is
specified, it is interpreted as C<< '<= $version' >> (to preserve the intent
that versions at or below the version specified are those considered to be
broken).  It is possible that this interpretation will be removed in the
future; almost certainly before C<breaks> becomes a formal part of the meta
specification.

=head1 CONFIGURATION

=head2 C<conflicts_module>

The name of the conflicts module to load and upon which to invoke the C<check_conflicts>
method. Defaults to the name of the main module with 'C<::Conflicts>'
appended, such as what is generated by the
L<[Conflicts]|Dist::Zilla::Plugin::Conflicts> plugin.

If your distribution uses L<Moose> but does not itself generate a conflicts
plugin, then C<Moose::Conflicts> is an excellent choice, as there are numerous
interoperability conflicts catalogued in that module.

There is no error if the module does not exist. This test does not require
L<[Conflicts]|Dist::Zilla::Plugin::Conflicts> to be used in your distribution;
this is only a feature added for backwards compatibility.

=head2 C<no_forced_deps>

Suitable for distributions that do not wish to add a C<test requires>
prerequisite on L<CPAN::Meta::Requirements> and L<CPAN::Meta::Check> --
instead, the dependencies will be added as C<test suggests>, and the generated
test will gracefully skip checks if these modules are not available.

Available since version 0.014.

=for Pod::Coverage filename gather_files munge_files register_prereqs

=head1 BACKGROUND

=for stopwords irc

I came upon this idea for a test after handling a
L<bug report|https://rt.cpan.org/Ticket/Display.html?id=92780>
I've seen many times before when dealing with L<Moose> code: "hey, when I
updated Moose, my other thing that uses Moose stopped working!"  For quite
some time Moose has generated breakage information in the form of the
F<moose-outdated> executable and a check in F<Makefile.PL> (which uses the
generated module C<Moose::Conflicts>), but the output is usually buried in the
user's install log or way up in the console buffer, and so doesn't get acted
on nearly as often as it should.  I realized it would be a simple matter to
re-run the executable at the very end of tests by crafting a filename that
always sorts (and runs) last, and further that we could generate this test.
This coincided nicely with conversations on irc C<#toolchain> about the
C<x_breaks> metadata field and plans for its future. Therefore, this
distribution, and its sister plugin L<[Breaks]|Dist::Zilla::Plugin::Breaks>
were born!

=head1 SEE ALSO

=for :list
* L<Dist::Zilla::Plugin::Breaks>
* L<Dist::CheckConflicts>
* L<The Annotated Lancaster Consensus|http://www.dagolden.com/index.php/2098/the-annotated-lancaster-consensus/> at "Improving on 'conflicts'"
* L<Module::Install::CheckConflicts>

=cut

__DATA__
___[ test-check-breaks ]___
use strict;
use warnings;

# this test was generated with {{ ref $plugin }} {{ $plugin->VERSION }}

use Test::More tests => {{ $test_count }};

SKIP: {
{{
    if ($module) {
        require Module::Runtime;
        my $filename = Module::Runtime::module_notional_filename($module);
        <<"CHECK_CONFLICTS";
    eval 'require $module; ${module}->check_conflicts';
    skip('no $module module found', 1) if not \$INC{'$filename'};

    diag \$@ if \$@;
    pass 'conflicts checked via $module';
CHECK_CONFLICTS
    }
    else
    {
        "    skip 'no conflicts module found to check against', 1;\n";
    }
}}}

{{
    if (keys %$breaks)
    {
        my $dumper = Data::Dumper->new([ $breaks ], [ 'breaks' ]);
        $dumper->Sortkeys(1);
        $dumper->Indent(1);
        $dumper->Useqq(1);
        my $dist_name = $dist->name;
        ($no_forced_deps ? 'SKIP: {' . "\n" : '')
        . '# this data duplicates x_breaks in META.json' . "\n"
        . 'my ' . $dumper->Dump

        . "\n" . join("\n", $no_forced_deps
            ?
                (map { "skip 'This information-only test requires $_', 0\n    if not eval 'require $_';" }
                    'CPAN::Meta::Requirements', 'CPAN::Meta::Check')
            :
                ('use CPAN::Meta::Requirements;', "use CPAN::Meta::Check $cmc_prereq;"))
        . "\n\n"

    . <<'CHECK_BREAKS_1b'
my $reqs = CPAN::Meta::Requirements->new;
$reqs->add_string_requirement($_, $breaks->{$_}) foreach keys %$breaks;

our $result = CPAN::Meta::Check::check_requirements($reqs, 'conflicts');

if (my @breaks = grep { defined $result->{$_} } keys %$result)
{
CHECK_BREAKS_1b
    . "    diag 'Breakages found with $dist_name:';\n"
    . <<'CHECK_BREAKS_2'
    diag "$result->{$_}" for sort @breaks;
    diag "\n", 'You should now update these modules!';
}
CHECK_BREAKS_2
        . ($no_forced_deps ? '}' . "\n" : '')
    }
    else { q{pass 'no x_breaks data to check';} . "\n" }
}}
