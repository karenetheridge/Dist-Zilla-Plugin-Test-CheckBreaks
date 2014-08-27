use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Deep;
use Path::Tiny;
use File::pushd 'pushd';

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ 'Test::CheckBreaks' => ],
                ),
                path(qw(source lib Foo Bar.pm)) => "package Foo::Bar;\n1;\n",
                path(qw(source lib Foo Bar Conflicts.pm)) => <<CONFLICTS,
package Foo::Bar::Conflicts;
sub check_conflicts {}
1;
CONFLICTS
            },
        },
    );

    $tzil->chrome->logger->set_debug(1);
    $tzil->build;

    my $build_dir = path($tzil->tempdir)->child('build');
    my $file = path($build_dir, 't', 'zzz-check-breaks.t');
    ok(-e $file, 'test created');

    my $content = $file->slurp;
    unlike($content, qr/[^\S\n]\n/m, 'no trailing whitespace in generated test');

    like($content, qr/eval 'require $_; $_->check_conflicts'/m, "test checks $_")
        for 'Foo::Bar::Conflicts';

    cmp_deeply(
        $tzil->distmeta,
        superhashof({
            prereqs => {
                test => {
                    requires => {
                        'Test::More' => '0.88',
                        'Module::Runtime' => '0',
                    },
                },
            },
        }),
        'prereqs are properly injected for the test phase',
    ) or diag 'got distmeta: ', explain $tzil->distmeta;

    subtest 'run the generated test' => sub
    {
        my $wd = pushd $build_dir;
        do $file;
        note 'ran tests successfully' if not $@;
        fail($@) if $@;
    };

    diag 'saw log messages: ', explain $tzil->log_messages if not Test::Builder->new->is_passing;
}

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ 'Test::CheckBreaks' => ],
                ),
                path(qw(source lib Foo Bar.pm)) => "package Foo::Bar;\n1;\n",
            },
        },
    );

    $tzil->chrome->logger->set_debug(1);
    $tzil->build;

    my $build_dir = path($tzil->tempdir)->child('build');
    my $file = path($build_dir, 't', 'zzz-check-breaks.t');
    ok(-e $file, 'test created');

    my $content = $file->slurp;
    unlike($content, qr/[^\S\n]\n/m, 'no trailing whitespace in generated test');

    unlike($content, qr/$_/m, "test does not do anything with $_")
        for 'Foo::Bar::Conflicts';

    cmp_deeply(
        $tzil->distmeta,
        superhashof({
            prereqs => {
                test => {
                    requires => {
                        'Test::More' => '0.88',
                    },
                },
            },
        }),
        'prereqs are properly injected for the test phase',
    ) or diag 'got distmeta: ', explain $tzil->distmeta;

    subtest 'run the generated test' => sub
    {
        pushd $build_dir;
        do $file;
        warn $@ if $@;
    };

    diag 'saw log messages: ', explain $tzil->log_messages if not Test::Builder->new->is_passing;
}

done_testing;
