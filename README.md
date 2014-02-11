# NAME

Dist::Zilla::Plugin::Test::CheckBreaks - Generate a test that shows your conflicting modules

# VERSION

version 0.003

# SYNOPSIS

In your `dist.ini`:

    [Breaks]
    Foo = <= 1.1    ; Foo at 1.1 or lower will break when I am installed

    [CheckBreaks]
    conflicts_module = Moose::Conflicts

# DESCRIPTION

This is a [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla) plugin that runs at the
[gather files](https://metacpan.org/pod/Dist::Zilla::Role::FileGatherer) stage, providing a test file
that runs last in your test suite and checks for conflicting modules, as
indicated by `x_breaks` in your distribution metadata.
(See the `t/zzz-check-breaks.t` test in this distribution for an example.)

`x_breaks` entries are expected to be
[version ranges](https://metacpan.org/pod/CPAN::Meta::Spec#Version-Ranges), with one
addition, for backwards compatibility with
[\[Conflicts\]](https://metacpan.org/pod/Dist::Zilla::Plugin::Conflicts): if a bare version number is
specified, it is interpreted as `'<= $version'` (to preserve the intent
that versions at or below the version specified are those considered to be
broken).  It is possible that this interpretation will be removed in the
future; almost certainly before `breaks` becomes a formal part of the meta
specification.

# CONFIGURATION

## `conflicts_module`

The name of the conflicts module to load and upon which to invoke the `check_conflicts`
method. Defaults to the name of the main module with '`::Conflicts`'
appended, such as what is generated by the
[\[Conflicts\]](https://metacpan.org/pod/Dist::Zilla::Plugin::Conflicts) plugin.

If your distribution uses [Moose](https://metacpan.org/pod/Moose) but does not itself generate a conflicts
plugin, then `Moose::Conflicts` is an excellent choice, as there are numerous
interoperability conflicts catalogued in that module.

There is no error if the module does not exist. This test does not require
[\[Conflicts\]](https://metacpan.org/pod/Dist::Zilla::Plugin::Conflicts) to be used in your distribution;
this is only a feature added for backwards compatibility.

# BACKGROUND

I came upon this idea for a test after handling a
[bug report](https://rt.cpan.org/Ticket/Display.html?id=92780)
I've seen many times before when dealing with [Moose](https://metacpan.org/pod/Moose) code: "hey, when I
updated Moose, my other thing that uses Moose stopped working!"  For quite
some time Moose has generated breakage information in the form of the
`moose-outdated` executable and a check in `Makefile.PL` (which uses the
generated module `Moose::Conflicts`), but the output is usually buried in the
user's install log or way up in the console buffer, and so doesn't get acted
on nearly as often as it should.  I realized it would be a simple matter to
re-run the executable at the very end of tests by crafting a filename that
always sorts (and runs) last, and further that we could generate this test.
This coincided nicely with conversations on irc `#toolchain` about the
`x_breaks` metadata field and plans for its future. Therefore, this
distribution, and its sister plugin [\[Breaks\]](https://metacpan.org/pod/Dist::Zilla::Plugin::Breaks)
were born!

# SEE ALSO

- [Dist::Zilla::Plugin::Breaks](https://metacpan.org/pod/Dist::Zilla::Plugin::Breaks)
- [Dist::CheckConflicts](https://metacpan.org/pod/Dist::CheckConflicts)
- [The Annotated Lancaster Consensus](http://www.dagolden.com/index.php/2098/the-annotated-lancaster-consensus/)
at "Improving on 'conflicts'"

# AUTHOR

Karen Etheridge <ether@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
