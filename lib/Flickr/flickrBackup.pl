#!/usr/bin/perl 

use strict;
use warnings;

use autodie;
use Carp;
use Data::Dumper;
use Getopt::Long;
use File::Basename;
use File::Path qw(remove_tree);
use LWP::Simple;

use PhotoBrowser;

# Key:
#  e5df46b2cf8cfe59f58df245ec09c9d4
#
# Secret:
#  e1b9e34909d1c9f2

sub logApp {
    my ($pb) = @_;
    my $token;

    if ( -e $ENV{HOME} . "/.FlickrBackup" ) {
        open my $fd, '<', $ENV{HOME} . "/.FlickrBackup";
        $token = scalar <$fd>;
        close $fd;

        $token = $pb->checkToken($token);
    }

    $token = $pb->login($token);

    open my $fd, '>', $ENV{HOME} . '/.FlickrBackup';
    print $fd $token;
    close $fd;

    return;
}

sub url2file {
    my ( $flickrPhoto, $path ) = @_;
    my ($extension) = $flickrPhoto->{url} =~ /\.(.{3,4}$)/;
    LWP::Simple::getstore( $flickrPhoto->{url},
        "$path/$flickrPhoto->{title}.$extension" )
      unless -e "$path/$flickrPhoto->{title}.$extension";

    return;
}

sub backupSet {
    my ( $fpb, $basePath, $set, $size ) = @_;

    ( my $safeTitle = $set->{title} ) =~ s/[\(\)\'\/]//g;
    print "SafeTitle: $safeTitle\n";

    my $path = "$basePath/$safeTitle";
    print "Mkdir:$path\n";
    mkdir $path unless -e $path;

    my @photos = @{ $fpb->getPicturesOfSet( $set->{id}, $size, 1, [] ) };
    foreach my $photo (@photos) {
        print "\tGetting photo... $photo->{title}\n";
        url2file( $photo, $path );
    }
    return;
}

sub backupCollection {
    my ( $fpb, $basePath, $collection, $size ) = @_;

    ( my $safeTitle = $collection->{title} ) =~ s/[\(\)\'\/]//g;
    print "SafeTitle:$safeTitle\n";

    my $path = "$basePath/$safeTitle";
    print "Mkdir:$path\n";
    mkdir $path unless -e $path;

    foreach my $element ( @{ $fpb->getCollections( $collection->{id} ) } ) {
        backupCollection( $fpb, $path, $element, $size );
        return;
    }
    foreach my $set ( @{ $fpb->getSetsOfCollections( $collection->{id} ) } ) {
        backupSet( $fpb, $path, $set, $size );
    }

}

sub flickrBackup {
    my ( $path, $size, $options ) = @_;
    my $clean     = $options->{clean};
    my $albumName = $options->{name};

    remove_tree($path) && mkdir $path if -e $path && $clean;

    my $fpb = Flickr::PhotoBrowser->new(
        {
            key    => 'e5df46b2cf8cfe59f58df245ec09c9d4',
            secret => 'e1b9e34909d1c9f2',
        }
    );
    logApp($fpb);
    print Dumper($fpb);

    my ( $colId, $setId );
    if ($albumName) {
        $colId = $fpb->retrieveCollectionID($albumName);
        $setId = $fpb->retrieveSetID($albumName);

        print "ColId: $colId  SetId: $setId\n";

        if ( !$colId xor $setId ) {
            carp "Ambiguous name... matches with set and collection.\n"
              . "Retrieving collection by default";
            $setId = undef;
        }
    }

    if ( !( $colId || $setId ) ) {
        foreach my $collection ( @{ $fpb->getCollections() } ) {
            backupCollection( $fpb, $path, $collection, $size );
        }
    }
    else {
        if ($colId) {
            backupCollection( $fpb, $path,
                { id => $colId, title => $albumName }, $size );
        }
        else {
            backupSet( $fpb, $path, 
                { id => $setId, title => $albumName }, $size );
        }
    }
}

######################### MAIN ########################################
sub help {
    print "\n", basename($0), "\n", <DATA> and exit;
}

sub main {
    GetOptions(
        'path|p=s' => \( my $backupPath = undef ),
        'name|n=s' => \( my $albumName  = undef ),
        'size|s=s' => \( my $size       = 'url_t' ),
        'clean|c'  => \( my $cleanExec  = undef ),
        'help|h'   => \( my $printHelp  = undef ),
    );

    #url_sq, url_t, url_s, url_m, url_o

    help() if $printHelp;
    help() unless $backupPath;
    help() unless $size =~ /url_(:?[tsmo]|sq)/;

    flickrBackup( $backupPath, $size,
        { name => $albumName, clean => $cleanExec } );
}

main();

__DATA__






