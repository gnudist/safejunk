use strict;
use warnings;

package SJ::Dir;
use Moose;

has 'path' => ( is => 'rw', isa => 'Str', required => 1 );
has 'config_path' => ( is => 'rw', isa => 'Str', lazy => 1, builder => '_build_config_path' );
has 'revno_path' => ( is => 'rw', isa => 'Str', lazy => 1, builder => '_build_revno_path' );
has 'timestamp_path' => ( is => 'rw', isa => 'Str', lazy => 1, builder => '_build_timestamp_path' );
has 'filelist_path' => ( is => 'rw', isa => 'Str', lazy => 1, builder => '_build_filelist_path' );
has 'contents_path' => ( is => 'rw', isa => 'Str', lazy => 1, builder => '_build_contents_path' );

has 'config' => ( is => 'rw', isa => 'HashRef' );
has 'revno' => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_revno' );
has 'timestamp' => ( is => 'rw', isa => 'Int', lazy => 1, builder => '_build_timestamp' );
has 'managed_entries' => ( is => 'rw', isa => 'ArrayRef[Str]' );

use File::Spec ();
use JSON::XS 'decode_json';
use SJ::Util ();

use Carp::Assert 'assert';

sub _build_revno
{
	my $self = shift;

	my $rv = 0;

	if( -f $self -> revno_path() )
	{
		$rv = int( &SJ::Util::slurp( $self -> revno_path() ) or 0 );
	}

	return $rv;
}

sub _build_timestamp
{
	my $self = shift;

	my $rv = 0;

	if( -f $self -> timestamp_path() )
	{
		$rv = int( &SJ::Util::slurp( $self -> timestamp_path() ) or 0 );
	}

	return $rv;
}

sub bump_revno
{
	my $self = shift;

	return $self -> set_revno( $self -> revno() + 1 );
}

sub set_revno
{
	my ( $self, $revno ) = @_;

	assert( open( my $fh, '>', $self -> revno_path() ) );
	$fh -> print( $revno );
	$fh -> close();
	$self -> revno( $revno );

	return $revno;
}

sub set_timestamp
{
	my ( $self, $timestamp ) = @_;

	assert( open( my $fh, '>', $self -> timestamp_path() ) );
	$fh -> print( $timestamp );
	$fh -> close();
	$self -> timestamp( $timestamp );

	return $timestamp;
}

sub check_errs
{
	my $self = shift;

	my $err = undef;

	my $p = $self -> path();
	
	unless( $err )
	{
		if( -d $p )
		{
			if( -f $self -> config_path() )
			{
				1;
			} else
			{
				$err = 'Config file not found in this dir';
			}
			
		} else
		{
			$err = 'Dir does not exist';
		}
	}

	unless( $err )
	{
		unless( -f $self -> filelist_path() )
		{
			$err = 'File list registry not found';
		}
	}

	unless( $err )
	{
		my $data = &SJ::Util::slurp( $self -> filelist_path() );

		my $filelist = undef;

		eval
		{
			$filelist = decode_json( $data );
		};

		if( my $e = $@ )
		{
			$err = "Filelist parse error: " . $e;
		} elsif( my $what = ref( $filelist ) )
		{
			if( $what eq 'ARRAY' )
			{
				$self -> managed_entries( $filelist );
			} else
			{
				$err = "Bad filelist: " . $what;
			}
			
		} else
		{
			$err = "Uknown filelist: " . $what;
		}
	}
		

	unless( $err )
	{
		unless( -d $self -> contents_path() )
		{
			$err = 'Incomplete dir, no contents inside';
		}
	}

	unless( $err )
	{
		my $data = &SJ::Util::slurp( $self -> config_path() );

		my $config = undef;

		eval
		{
			$config = decode_json( $data );
		};

		if( my $e = $@ )
		{
			$err = "Config parse error: " . $e;
		} elsif( my $what = ref( $config ) )
		{
			if( $what eq 'HASH' )
			{
				$self -> config( $config );
			} else
			{
				$err = "Bad config: " . $what;
			}
			
		} else
		{
			$err = "Uknown config: " . $what;
		}
	}

	unless( $err )
	{
		my @mustbe = ( 'name', 'path', 'gpg_key_id', 'storage' );

HV35rvJ0xrQcNH1q:
		foreach my $m ( @mustbe )
		{
			unless( $self -> config() -> { $m } )
			{
				$err = 'Config must define ' . $m;
				last HV35rvJ0xrQcNH1q;

			}
		}
	}
	
	# unless( $err )
	# {
	# 	$err = 'Not implemented';
	# }
	
	return $err;
	
}

sub _build_config_path
{
	my $self = shift;

	my $rv = File::Spec -> catfile( $self -> path(), 'meta', 'conf' );

	return $rv;
}

sub _build_revno_path
{
	my $self = shift;

	my $rv = File::Spec -> catfile( $self -> path(), 'meta', 'revno' );

	return $rv;
}

sub _build_timestamp_path
{
	my $self = shift;

	my $rv = File::Spec -> catfile( $self -> path(), 'meta', 'timestamp' );

	return $rv;
}

sub _build_filelist_path
{
	my $self = shift;

	my $rv = File::Spec -> catfile( $self -> path(), 'meta', 'filelist' );

	return $rv;
}

sub _build_contents_path
{
	my $self = shift;

	my $rv = File::Spec -> catdir( $self -> path(), 'contents' );

	return $rv;
}

sub managed_entry_from_outside
{
	my ( $self, $e, $more ) = @_;

	my @rv = (); # can be subdir
	
	my $fp = File::Spec -> catfile( $self -> config() -> { 'path' }, $e );

	if( -f $fp )
	{
		push @rv, { $e => &SJ::Util::_one_file_entry( $fp ) };
		
	} elsif( -d $fp )
	{
		push @rv, { $e => &SJ::Util::_one_file_entry( $fp ) };

		my $should_descend = 1;

		if( $more and $more -> { 'only_dir' } )
		{
			$should_descend = 0;
		}

		if( $should_descend )
		{
		
			my @t1 = &SJ::Util::build_tree( $fp );
			my @t2 = ();

			my $remove = $self -> config() -> { 'path' };
				
			foreach my $f ( @t1 )
			{
				my @t = %{ $f };
				assert( scalar @t == 2 );

				$t[ 0 ] =~ s/\Q$remove\E//g;
				$t[ 0 ] =~ s/^[\/\\]//;
				
				push @t2, { $t[ 0 ] => $t[ 1 ] };
			}
		
			push @rv, @t2;
		}
		
	} else
	{
		if( $more and $more -> { 'missing_ok' } )
		{
			1;
		} else
		{
			assert( 0, "unknown: " . $fp );
		}
	}
	    

	return @rv;
}

1;
