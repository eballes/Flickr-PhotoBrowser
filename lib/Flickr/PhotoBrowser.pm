package Flickr::PhotoBrowser;

use strict;
use warnings;
use autodie;

use Carp;
use Data::Dumper;
use Flickr::API;
use List::MoreUtils qw{any all};

our $VERSION = '0.02';

=head1 NAME

Flickr::PhotoBrowser - A simple Perl Flickr API. 

=head1 SYNOPSIS

  use Flickr::PhotoBrowser;

  my $flickr =
    Flickr::Simple2->new({
        api_key => $cfg->param('Flickr.API_KEY'),
        api_secret => $cfg->param('Flickr.API_SHARED_SECRET'),
        auth_token => $cfg->param('Flickr.auth_token')
    });

=head1 DESCRIPTION

A XML::Simple based Perl Flickr API. 

=head2 EXPORT

None by default.

=cut

=head1 METHODS

=head2 new

=over 4

my $fpb = Flickr::PhotoBrowser->new(
    {
        key    => 'e5df46b2cf8cfe59f58df245ec09c9d4',
        secret => 'e1b9e34909d1c9f2',
    }
);

 C<key> is your Flickr API key given by Flickr. 
 C<secret> is your Flickr API secret key given by Flickr. 

=back

=cut

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

#-------------------------------------

=head2 login

=over 4

 $result = $fpb->login( { } );
 $result = $fpb->login( { token => $token } );
 $result = $fpb->login( { frob => $frob } );

Performs the login of the application.

 Requires: A hash reference with nothing or the keys token or frob.
 Returns: A hash reference which the following possible keys:
    {
        token => The token used if the app is logged correctly
        uri => The URL where to authorized the application
        frob => The frob used to get the URL. Needed for the
                second call after granting acess to the app.
    }

=back

=cut

sub login {
    my ( $self, $options ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    my $token = $options->{token};
    my $frob  = $options->{frob};

    if ( !$token ) {
        if ( !$frob ) {
            my $response = $self->{api}->execute_method('flickr.auth.getFrob');
            my $frob = _getValues( $response->{tree}, ['frob'] );

            return {
                uri  => $self->{api}->request_auth_url( 'read', $frob ),
                frob => $frob,
            };
        }
        else {
            my $response =
              $self->{api}
              ->execute_method( 'flickr.auth.getToken', { frob => $frob } );
            $token = _getValues( $response->{tree}, [ 'auth', 'token' ] );
        }
    }

    my $response =
      $self->{api}
      ->execute_method( 'flickr.auth.checkToken', { auth_token => $token } );

    if ( $response->{tree}{attributes}{stat} eq 'ok' ) {
        my ( $user, $nsid ) = _getValues(
            $response->{tree},
            [ 'auth',     'user' ],
            [ 'username', 'nsid' ]
        );

        $self->{user}  = $user;
        $self->{nsid}  = $nsid;
        $self->{token} = $token;

        return { token => $token };
    }
    else {
        return $self->login( {} );
    }
}

#-------------------------------------

=head2 checkToken

=over 4

$result = $fpb->checkToken($token);

Checks that the given token is valid.

 Requires: A token.
 Returns: The same token or null if it doesn't succeed.

=back

=cut

sub checkToken {
    my ( $self, $token ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    my $response =
      $self->{api}
      ->execute_method( 'flickr.auth.checkToken', { auth_token => $token } );
    $token = undef unless $response->{success};

    return $token;
}

#-------------------------------------

=head2 getCollections 

=over 4

$collections = $fpb->getCollections($collection_id);

Returns the list of collections at the root level of the flickr account if no
C<collection_id> is provided or otherwise the list of collections inside the 
given collection.

 Requires: Nothing, or a collection id.
 Returns: An array reference to a list of collections.
    Each collection is a hash reference with the following keys:
        id => Collection id
        title => Title of the collection
        descr => Description of the collection 

=back

=cut

sub getCollections {
    my ( $self, $col_id ) = @_;
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
                  && $collection->{name} eq 'collection';
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

#-------------------------------------

=head2 getSetsOfCollections 

=over 4

$sets = $fpb->getSetsOfCollections($collection_id);

Returns the list of sets inside the given collection. If no collection is
given, it returns all the sets.

 Requires: Nothing, or a collection id.
 Returns: An array reference to a list of sets.
    Each set is a hash reference with the following keys:
        id => Set id
        title => Title of the set 
        descr => Description of the set

=back

=cut

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

#-------------------------------------

=head2 getPicturesOfSet

=over 4

$photos = $fpb->getPicturesOfSet($set_id);

Returns the list of photos inside the given set. 

 Requires: A set id
 Returns: An array reference to a list of photos.
    Each photo is a hash reference with the following keys:
        url => URL of the photo
        title => Title of the photo

=back

=cut

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
          : return $self->getPicturesOfSet( $set_id, $size, ++$page, $photos );
    }
}

#-------------------------------------

=head2 retrieveSetID

=over 4

$id = $fpb->retrieveSetID($name);

Returns the id of a set given its name

 Requires: A set name
 Returns: The set id, or undef if it doesn't exist.

=back

=cut

sub retrieveSetID {
    my ( $self, $name ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    return $self->_retrieveID( $name, 'set' );
}

#-------------------------------------

=head2 retrieveCollectionID

=over 4

$id = $fpb->retrieveCollectionID($name);

Returns the id of a collection given its name

 Requires: A collection name
 Returns: The collection id, or undef if it doesn't exist.

=back

=cut

sub retrieveCollectionID {
    my ( $self, $name ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";

    return $self->_retrieveID( $name, 'collection' );
}

#-------------------------------------

=head2 isTheWantedSize

=over 4

$id = $fpb->isTheWantedSize($currentDimensions, $wishedSize);

 Requires: Current image dimensions (array ref to height and width)
    and flickr url_size of desired photo
 Returns: Boolean

=back

=cut

sub isTheWantedSize {
    my ( $self, $currentDimensions, $wishedSize ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";
    my %dimensionMatrix = (
        url_sq => 75,
        url_t  => 100,
        url_s  => 240,
        url_m  => 500,
        url_z  => 640,
        url_l  => 1024,
        url_o  => 1024,
    );

    if ( $wishedSize eq 'url_o' ) {
        return any { $_ > $dimensionMatrix{$wishedSize} } @$currentDimensions;
    }
    else {
        return any { $_ == $dimensionMatrix{$wishedSize} } @$currentDimensions;
    }
    return;
}

=head1 PRIVATE METHODS

=head2 _getValues

=over 4

$list = $fpb->_getValues($elements, $attributes);

Returns the values requested from Flickr's reply formatted in
XML::Parser::Lite::Tree format.

 Requires: An array reference representing the path to the desired element.
           An array reference of the set of attributes, if any, requested for
that element

 Returns: The list of attributes requested or the content of the node.

=back

=cut

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

=head2 _retrieveID

=over 4

$id = $fpb->_retrieveID($name, $type);

 Requires: The name of the collection/set and its type ('collection' or 'set')
 Returns: The id, or undef if it doesn't exist.

=back

=cut

sub _retrieveID {
    my ( $self, $name, $type, $col_id ) = @_;
    croak "OO use required\n"
      if ( ref $self ) ne "Flickr::PhotoBrowser";
    croak "Invalid type: $type != 'collection'|'set'"
      unless $type eq 'collection' || $type eq 'set';

    $col_id = 0 unless $col_id;
    my $response =
      $self->{api}->execute_method( 'flickr.collections.getTree',
        { user_id => $self->{nsid}, collection_id => $col_id } );

    foreach my $field ( @{ $response->{tree}{children} } ) {
        next unless $field->{name} && $field->{name} eq 'collections';
        foreach my $collection ( @{ $field->{children} } ) {
            next
              unless $collection->{name}
                  && $collection->{name} eq 'collection';

            if ( $type eq 'collection' ) {

                #print "Recursion! $collection->{attributes}{title}\n"
                #if $col_id ne $collection->{attributes}{id};
                my $recursion =
                  $self->_retrieveID( $name, $type,
                    $collection->{attributes}{id} )
                  if $col_id ne $collection->{attributes}{id};
                return $recursion if $recursion;
                next unless $collection->{attributes}{title} eq $name;
                return $collection->{attributes}{id};
            }
            else {
                foreach my $set ( @{ $collection->{children} } ) {
                    next unless $set->{name};
                    if ( $set->{name} eq 'collection' ) {

                        #print "Recursion! $collection->{attributes}{title}\n"
                        #if $col_id ne $collection->{attributes}{id};
                        my $recursion =
                          $self->_retrieveID( $name, $type,
                            $collection->{attributes}{id} )
                          if $col_id ne $collection->{attributes}{id};
                        return $recursion if $recursion;
                    }
                    else {

                        #print "Set: $set->{attributes}{title}\n";
                        next unless $set->{attributes}{title} eq $name;
                        return $set->{attributes}{id};
                    }
                }
            }
        }
    }
    return;
}

1
