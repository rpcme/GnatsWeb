# Copyright (C) 2015 Richard Elberger

use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Gnatsweb',
    VERSION_FROM  => 'script/gnatsweb.pl',
    ABSTRACT_FROM => 'script/gnatsweb.pl',
    AUTHOR        => 'Richard Elberger',
    INSTALLDIRS   => ($] >= 5.008001 ? 'perl' : 'site'),
    EXE_FILES     => [ 'script/gnatsweb.pl',
                       'script/gnatsweb-site.pl',
                       'script/gnatsweb-site-example.pl' ],
    PREREQ_PM => {
        'Carp'           => 0,
        'Cwd'            => 0,
        'File::Basename' => 0,
        'File::Spec'     => 0,
        ( eval { $] < 5.006 } ? ( 'Symbol' => 0 ) : () ),
    },
    clean => {
        FILES => 'cover_db test-*',
    },
    (eval { ExtUtils::MakeMaker->VERSION(6.46) } ? ( META_MERGE => {
      'meta-spec' => { version => 2 },
      resources => {
        repository  => {
          url  => 'https://github.com/rpcme/Gnatsweb.git',
          web  => 'https://github.com/rpcme/Gnatsweb',
          type => 'git',
        },
      },
      license => 'perl',
    }) : () ),
);
