package Flickr::PhotoBrowser;

use strict;
use warnings;
use autodie;

use Carp;
use Data::Dumper;
use Flickr::API;

# Key:
#  e5df46b2cf8cfe59f58df245ec09c9d4
#
# Secret:
#  e1b9e34909d1c9f2

our $VERSION = '0.01';

sub _getValues {
    my ( $tree, $elements, $attr ) = @_;

    croak "Not a valid response\n" . Dumper($tree)
      unless defined $tree->{children};

    foreach my $field ( @{ $tree->{children} } ) {
        next unless $field->{name} && $field->{name} eq $elements->[0];

        shift @{$elements};
        if ( defined $elements->[0] && defined $field->{children} ) {

            #print "Recursive call\n";
            return _getValues( $field, $elements, $attr );
        }
        else {
            $attr
              ? return map { $field->{attributes}{$_} } @{$attr}
              : return $field->{children}[0]{content};
        }
    }

    return;
}

sub _getToken {
    my ($self) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    return unless -e $ENV{HOME} . "/.FlickrBrowser";

    open my $fd, '<', $ENV{HOME} . "/.FlickrBrowser";
    my $token = scalar <$fd>;
    close $fd;

    my $response =
      $self->{api}
      ->execute_method( 'flickr.auth.checkToken', { auth_token => $token } );
    $response->{success}
      ? return $token
      : return;
}

sub new {
    my ( $class, $options ) = @_;
    my $api = new Flickr::API(
        {
            'key'    => 'e5df46b2cf8cfe59f58df245ec09c9d4',
            'secret' => 'e1b9e34909d1c9f2'
        }
    );

    my $self = { api => $api };
    bless $self, $class;
}

sub login {
    my ($self) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    my $response = $self->{api}->execute_method('flickr.auth.getFrob');
    my $frob = _getValues( $response->{tree}, ['frob'] );

    if ( !$self->_getToken() ) {
        chomp( my $browser = `which firefox` || `which google-chrome` );
        my $uri = $self->{api}->request_auth_url( 'read', $frob );

        system( $browser, $uri );
        print "Go to\n-> $uri\nand grant read access to PhotoBroser\n";
        print "Press enter to continue when finished.\n";

        $response =
          $self->{api}
          ->execute_method( 'flickr.auth.getToken', { frob => $frob } );
        my $token = _getValues( $response->{tree}, [ 'auth', 'token' ] );

        open my $fd, '>', $ENV{HOME} . '/.FlickrBrowser';
        print $fd $token;
        close $fd;
    }

    my $token = $self->_getToken();
    $response =
      $self->{api}
      ->execute_method( 'flickr.auth.checkToken', { auth_token => $token } );

    my ( $user, $nsid ) = _getValues(
        $response->{tree},
        [ 'auth',     'user' ],
        [ 'username', 'nsid' ]
    );

    return { user => $user, nsid => $nsid, token => $token };
}

sub getCollections {
    my ( $self, $nsid, $col_id ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    my @collections = ();
    my $response =
      $self->{api}->execute_method( 'flickr.collections.getTree',
        { user_id => $nsid, collection_id => $col_id } );

    foreach my $field ( @{ $response->{tree}{children} } ) {
        next unless $field->{name} && $field->{name} eq 'collections';
        foreach my $collection ( @{ $field->{children} } ) {
            next
              unless $collection->{name}
                  && $collection->{name} =~ /collection|set/;
            next
              unless !$col_id
                  || (   $collection->{attributes}{id}
                      && $collection->{attributes}{id} ne $col_id );
            push @collections,
              {
                title => $collection->{attributes}{title},
                id    => $collection->{attributes}{id},
                descr => $collection->{attributes}{description},
              };
        }
    }

    return \@collections;
}

sub getSetsOfCollections {
    my ( $self, $nsid, $col_id ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";
    my @sets = ();

    my $response =
      $self->{api}->execute_method( 'flickr.collections.getTree',
        { user_id => $nsid, collection_id => $col_id } );

    foreach my $field ( @{ $response->{tree}{children} } ) {
        next unless $field->{name} && $field->{name} eq 'collections';
        foreach my $collection ( @{ $field->{children} } ) {
            next
              unless $collection->{name}
                  && $collection->{name} eq 'collection';
            foreach my $set ( @{ $collection->{children} } ) {
                next unless $set->{name} && $set->{name} eq 'set';
                push @sets,
                  {
                    title => $set->{attributes}{title},
                    id    => $set->{attributes}{id},
                    descr => $set->{attributes}{description},
                  };
            }
        }
    }

    return \@sets;
}

sub getPicturesOfSet {
    my ( $self, $token, $set_id, $size, $page, $photos ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    my $response = $self->{api}->execute_method(
        'flickr.photosets.getPhotos',
        {
            auth_token  => $token,
            photoset_id => $set_id,
            extras      => $size,
            per_page    => 500,
            page        => $page,
        }
    );

    foreach my $field ( @{ $response->{tree}{children} } ) {
        next unless $field->{name} && $field->{name} eq 'photoset';
        foreach my $photo ( @{ $field->{children} } ) {
            next
              unless $photo->{name}
                  && $photo->{name} eq 'photo';
            push @{$photos},
              {
                url   => $photo->{attributes}{$size},
                title => $photo->{attributes}{title},
              };
        }
        print scalar @{$photos};
        getc;
        $field->{attributes}{pages} == $field->{attributes}{page}
          ? return $photos
          : return $self->getPicturesOfSet( $token, $set_id, $size, ++$page,
            $photos );
    }
}

__END__
### TMP TESTS ###
my $fpb = Flickr::PhotoBrowser->new();
my $res = $fpb->login();
print "User: $res->{user} Nsid: $res->{nsid} Token: $res->{token}\n";

#print Dumper($fpb->getCollections($res->{nsid}));
#print Dumper($fpb->getCollections($res->{nsid}, '3641781-72157625104011405'));
#print Dumper($fpb->getSetsOfCollections($res->{nsid}, '3641781-72157606006060144'));
#print Dumper($fpb->getSetsOfCollections($res->{nsid}, '3641781-72157625104011405'));
#print Dumper($fpb->getCollections($res->{nsid}, '3641781-72157606006060144'));
#print Dumper($fpb->getPicturesOfSet('72157625376425032', 'url_o', 1, []));
#print Dumper($fpb->getPicturesOfSet($res->{token}, '72157603530249047', 'url_o', 1, []));
