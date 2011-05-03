package Flickr::PhotoBrowser;

use strict;
use warnings;
use autodie;

use Carp;
use Data::Dumper;
use Flickr::API;

our $VERSION = '0.01';

sub _getValues {
    my ( $tree, $elements, $attr ) = @_;

    croak "Not a valid response\n" . Dumper($tree)
      unless defined $tree->{children};

    foreach my $field ( @{ $tree->{children} } ) {
        next unless $field->{name} && $field->{name} eq $elements->[0];

        shift @{$elements};
        if ( defined $elements->[0] && defined $field->{children} ) {
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

sub _retrieveID { 
    my ( $self, $name, $type ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";
    croak "Invalid type: $type != 'collection'|'set'"
      unless $type eq 'collection' || $type eq 'set';
    
    my $response =
      $self->{api}->execute_method( 'flickr.collections.getTree',
        { user_id => $self->{nsid} } );

    foreach my $field ( @{ $response->{tree}{children} } ) {
        next unless $field->{name} && $field->{name} eq 'collections';
        foreach my $collection ( @{ $field->{children} } ) {
            next
              unless $collection->{name}
                  && $collection->{name} eq 'collection';

            if ($type eq 'collection') {
                next unless $collection->{attributes}{title} eq $name;
                return $collection->{attributes}{id};
            } else {
                foreach my $set ( @{ $collection->{children} } ) {
                    next unless $set->{name} && $set->{name} eq 'set';
                    next unless $set->{attributes}{title} eq $name;
                    return $set->{attributes}{id};
                }
            } 
        }
    }
    return;
}

sub new {
    my ( $class, $options ) = @_;
    my $api = new Flickr::API(
        {
            'key'    => $options->{key},
            'secret' => $options->{secret},
        }
    );

    my $self = { api => $api };
    bless $self, $class;
}

sub login {
    my ($self, $token) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    if ( !$token ) {
        my $response = $self->{api}->execute_method('flickr.auth.getFrob');
        my $frob = _getValues( $response->{tree}, ['frob'] );

        chomp( my $browser = `which firefox` || `which google-chrome` );
        my $uri = $self->{api}->request_auth_url( 'read', $frob );

        system( $browser, $uri );
        print "Go to\n-> $uri\nand grant read access to PhotoBroser\n";
        print "Press enter to continue when finished.\n"; 
        getc;

        $response =
          $self->{api}
          ->execute_method( 'flickr.auth.getToken', { frob => $frob } );
        $token = _getValues( $response->{tree}, [ 'auth', 'token' ] );

    }

    my $response =
      $self->{api}
      ->execute_method( 'flickr.auth.checkToken', { auth_token => $token } );

    my ( $user, $nsid ) = _getValues(
        $response->{tree},
        [ 'auth',     'user' ],
        [ 'username', 'nsid' ]
    );

    $self->{user} = $user; 
    $self->{nsid} = $nsid; 
    $self->{token} = $token;

    return $token;
}

sub checkToken {
    my ($self, $token) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    my $response =
      $self->{api}
      ->execute_method( 'flickr.auth.checkToken', { auth_token => $token } );
    $token = undef unless $response->{success};

    return $token;
}

sub getCollections {
    my ( $self,  $col_id ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";
    croak "User needs to be logged in first"
        unless $self->{nsid};

    my @collections = ();
    my $response =
      $self->{api}->execute_method( 'flickr.collections.getTree',
        { user_id => $self->{nsid}, collection_id => $col_id } );

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
    my ( $self, $col_id ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";
    croak "User needs to be logged in first"
        unless $self->{nsid};
    my @sets = ();

    my $response =
      $self->{api}->execute_method( 'flickr.collections.getTree',
        { user_id => $self->{nsid}, collection_id => $col_id } );

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
    my ( $self, $set_id, $size, $page, $photos ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";
    croak "User needs to be logged in first"
        unless $self->{token};

    my $response = $self->{api}->execute_method(
        'flickr.photosets.getPhotos',
        {
            auth_token  => $self->{token},
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
        $field->{attributes}{pages} == $field->{attributes}{page}
          ? return $photos
          : return $self->getPicturesOfSet( $set_id, $size, ++$page,
            $photos );
    }
}

sub retrieveSetID {
    my ( $self, $name ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    return $self->_retrieveID($name, 'set');
}

sub retrieveCollectionID {
    my ( $self, $name ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    return $self->_retrieveID($name, 'collection');
}

1;

