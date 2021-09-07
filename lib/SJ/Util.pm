use strict;
use warnings;

package SJ::Util;

use Carp::Assert 'assert';
use Digest::MD5 ();
use Data::Dumper 'Dumper';
use File::Spec ();

sub slurp
{
	my $fn = shift;

	assert( open( my $fh, '<', $fn ) );
	my $rv = join( '', <$fh> );
	$fh -> close();

	return $rv;
}

sub build_tree
{
	my ( $dir, $depth ) = @_;

	$depth = ( $depth or 0 );
	assert( $depth < 100, "that'd be too deep" );
	assert( -d $dir );

	my @rv = ();

	assert( opendir( my $dh, $dir ) );

Wb9NFm_1vywei3Wt:
	while( my $entry = readdir( $dh ) )
	{
		if( ( $entry eq '.' ) or ( $entry eq '..' ) )
		{
			next Wb9NFm_1vywei3Wt;
		}

		my $fullpath = File::Spec -> catfile( $dir, $entry );

		if( -f $fullpath )
		{
			my $k = $fullpath;
			push @rv, { $k => &_one_file_entry( $fullpath ) };
			
		} elsif( -d $fullpath )
		{
			my $k = $fullpath;
			push @rv, { $k => &_one_file_entry( $fullpath ) };
			push @rv, &build_tree( $fullpath, $depth + 1 );
		} else
		{
			assert( 0, "don't know how to handle " . $fullpath );
		}
	}
	
	closedir( $dh );
	
	return @rv;
}

sub _one_file_entry
{
	my $fp = shift;

	my %rv = ( fullpath => $fp );

	my @s = stat( $fp );
	$rv{ 'mode' } = $s[ 2 ];
	$rv{ 'atime' } = $s[ 8 ];
	$rv{ 'mtime' } = $s[ 9 ];
	$rv{ 'ctime' } = $s[ 10 ];
	$rv{ 'size' } = $s[ 7 ];

	if( -f $fp )
	{
		$rv{ 'md5' } = &file_md5( $fp );
	} elsif( -d $fp )
	{
		delete $rv{ 'size' };
	}

	return \%rv;
}

sub dir_separator
{
	my $rv = File::Spec -> catfile( '', '' );
	
	return $rv;
}

sub file_md5
{
	my $path = shift;
	my $rc = 0;

	if( open( my $fh, "<", $path ) )
	{
		binmode( $fh );
		$rc = Digest::MD5 -> new() -> addfile( $fh ) -> hexdigest();
		close( $fh );
	}

	return $rc;
}

sub compare_two_entries
{
	my ( $e1, $e2 ) = @_;

	my @f = ( 'mode', 'mtime', 'size', 'md5' ); # atime, ctime ?

	my $diff = undef;

	foreach my $f ( @f )
	{
		# assert( defined $e1 -> { $f }, Dumper( $e1 ) );
		# assert( defined $e2 -> { $f }, Dumper( $e2 ) );
		
		unless( ( $e1 -> { $f } or '' ) # dir entries won't have md5
			eq
			( $e2 -> { $f } or '' ) )
		{
			unless( $diff )
			{
				$diff = [];
			}
			push @{ $diff }, $f;
		}
	}
	
	return $diff;
}

1;
