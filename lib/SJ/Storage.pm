use strict;
use warnings;

package SJ::Storage;
use Moose;
with 'SJ::Msg';

has 'config' => ( is => 'rw', isa => 'HashRef', required => 1 );

use File::Temp ( 'tmpnam' );
use Carp::Assert 'assert';
use SJ::Util ();
use Data::Dumper 'Dumper';

sub push_file
{
	my ( $self, $file ) = @_;

	assert( my $config = $self -> config() );
	assert( my $method = $config -> { 'name' } );

	if( $method eq 'scp' )
	{
		assert( my $storage_path = $config -> { 'path' } );
		$self -> msg( 'scp-ing', $file, 'to', $storage_path );
		my $rc = &SJ::Util::scp( $file,
					 $storage_path );

		if( $rc -> { 'rc' } == 0 )
		{
			$self -> msg( "succes" );
		} else
		{
			$self -> msg( "error?", &SJ::Util::slurp( $rc -> { 'err' } ), Dumper( $rc ) );
		}
		
		
	} else
	{
		assert( 0, 'unsupported storage method ' . $method );
	}
	

	return 0;
}

sub pull_latest
{
	my $self = shift;

	my $rv = tmpnam();
	assert( my $storage_path = $self -> config() -> { 'path' }, Dumper( $self -> config() ) );

	$self -> msg( 'scp-ing', $storage_path, 'to', $rv );
	my $rc = &SJ::Util::scp( $storage_path,
				 $rv );
	
	if( $rc -> { 'rc' } == 0 )
	{
		$self -> msg( "succes" );
	} else
	{
		$self -> msg( "error?", &SJ::Util::slurp( $rc -> { 'err' } ), Dumper( $rc ) );
	}

	return $rv;
}

1;
