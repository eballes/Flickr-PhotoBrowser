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

    if (-e $ENV{HOME} . "/.FlickrBackup") {
        open my $fd, '<', $ENV{HOME} . "/.FlickrBackup";
        $token = scalar <$fd>;
        close $fd;

        $token = $pb->checkToken($token);
    }

    my $logInfo = $pb->login($token);

    open my $fd, '>', $ENV{HOME} . '/.FlickrBackup';
    print $fd $logInfo->{token};
    close $fd;

    return $logInfo;
}

sub url2file {
    my ($flickrPhoto, $path) = @_;
    LWP::Simple::getstore( $flickrPhoto->{url}, "$path/$flickrPhoto->{title}" );

    return;
}

sub flickrBackup {
    my ($path) = @_;

    -e $path ?
        remove_tree($path) && mkdir $path :
        mkdir $path;

    my $fpb = Flickr::PhotoBrowser->new( {
        key => 'e5df46b2cf8cfe59f58df245ec09c9d4', 
        secret => 'e1b9e34909d1c9f2',
    });
    my $loginData = logApp($fpb);

    print Dumper($loginData), "\n";
}




######################### MAIN ########################################
sub help {
    print "\n./", basename($0), " -s <station> [-v]", "\n\n";
    
}

sub main {
    GetOptions(
        'path|p=s' => \( my $backupPath = undef ),
        'help|h'    => \( my $printHelp = undef ),
    );

    help() if $printHelp;
    help() unless $backupPath;

    flickrBackup($backupPath);
}

main();

