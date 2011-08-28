use 5.10.1;
use ExtUtils::MakeMaker;

sub MY::postamble {
    return <<END;
ChangeLog: Makefile
\tgit log --pretty=fuller --decorate . > ChangeLog

META.yml: Makefile
\ttouch META.yml

END
}

WriteMakefile(
    NAME          => 'Flickr::PhotoBrowser',
    VERSION_FROM  => 'lib/Flickr/PhotoBrowser.pm',
    ABSTRACT_FROM => 'lib/Flickr/PhotoBrowser.pm',
    AUTHOR        => 'Eduardo Ballesteros <eballes@gmail.com>',
    PREREQ_PM     => {
        'Carp'           => 0,
        'File::Basename' => 0,
        'File::Path'     => 0,
        'LWP::Simple'    => 5.8,
        'Getopt::Long'   => 1,
        'Flickr::API'    => 0.07,
        'Image::Size'    => 3.230,
    },
    'EXE_FILES' => ['bin/flickrBackup'],
    'clean'     => { FILES => 'ChangeLog META.yml' },
    'depend'    => { 'create_distdir' => 'ChangeLog  META.yml' },
);
