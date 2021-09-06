use strict;
use warnings;

package SJ::Util;

use Carp::Assert 'assert';
use Digest::MD5 ();

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
	}

	return \%rv;
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

	my @f = ( 'mode', 'atime', 'ctime', 'mtime', 'size', 'md5' );

	my $diff = undef;

	foreach my $f ( @f )
	{
		unless( $e1 -> { $f } eq $e2 -> { $f } )
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
