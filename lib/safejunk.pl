#!/usr/bin/perl

use strict;
use warnings;

use lib ".";

package Safejunk;
use Moose;
extends 'SJ::App';

has 'cmd_line' => ( is => 'rw', isa => 'ArrayRef[Str]' );
has 'version' => ( is => 'ro', isa => 'Str', default => '0.01' );

use SJ::Dir ();
use SJ::Util ();
use Data::Dumper 'Dumper';
use Carp::Assert 'assert';
use File::Copy 'copy';
use File::Path ( 'remove_tree' );

sub app_mode_default
{
	my $self = shift;

	$self -> msg( "Safejunk ver.", $self -> version(), "starting" );

	if( my $action = $self -> cmd_line() -> [ 0 ] )
	{
		if( $action eq 'ur' )
		{
			$self -> action_update_rep();
			
		} elsif( $action eq 'rr' )
		{
			$self -> action_restore_from_rep();
		} else
		{
			$self -> msg( "don't know how to:", $action );
		}
	
	} else
	{
		$self -> msg( "specify action or go away" );
	}
	
	$self -> msg( "exit" );

	return 0;
}

# Упаковка - берём текущее состояние, обновляем реп из него,
# пакуем. Т.е. мастер - текущее положение дел.
sub action_update_rep
{
	my $self = shift;

	if( my $path = $self -> cmd_line() -> [ 1 ] )
	{
		my $d = SJ::Dir -> new( path => $path );

		if( my $err = $d -> check_errs() )
		{
			$self -> msg( "injalid Safejunk dir", $path, ":", $err );
		} else
		{
			$self -> msg( "path is ok, continuing" );

			my %safe_contents = ();

			{
				my @safe_contents = &SJ::Util::build_tree( $d -> contents_path() );

				my $remove = $d -> contents_path();
				
				foreach my $f ( @safe_contents )
				{
					my @t = %{ $f };
					assert( scalar @t == 2 );

					$t[ 0 ] =~ s/\Q$remove\E//g;
					$t[ 0 ] =~ s/^[\/\\]//;

					$safe_contents{ $t[ 0 ] } = $t[ 1 ];
				}
			}

			my %actual_contents = ();

			foreach my $e ( @{ $d -> managed_entries() } )
			{
				my @t = $d -> managed_entry_from_outside( $e );

				foreach my $t ( @t )
				{
					my @t1 = %{ $t };
					assert( scalar @t1 == 2 );
					$actual_contents{ $t1[ 0 ] } = $t1[ 1 ];
				}
			}

			foreach my $e ( @{ $d -> managed_entries() } )
			{
				my $s = &SJ::Util::dir_separator();
				my @parts = split( /\Q$s\E/, $e );

				if( scalar @parts > 1 )
				{
					my @t = ();
					foreach my $p ( @parts )
					{
						push @t, $p;
						my $p1 = join( $s, @t );

						unless( exists $actual_contents{ $p1 } )
						{
							my @t = $d -> managed_entry_from_outside( $p1, { only_dir => 1 } );

							foreach my $t ( @t )
							{
								my @t1 = %{ $t };
								assert( scalar @t1 == 2 );
								$actual_contents{ $t1[ 0 ] } = $t1[ 1 ];
							}
						}
					}
				}
			}

			

			my ( $to_remove, $to_add, $to_update ) = $self -> pack_compare_popout( \%safe_contents, \%actual_contents );
			
			my @to_remove = @{ $to_remove };
			my @to_add = @{ $to_add };
			my %to_update = %{ $to_update };
			my $need_to_bump_revision = 0;

			if( @to_remove )
			{
				foreach my $t ( sort { &fnsrt( $b ) cmp &fnsrt( $a ) } @to_remove )
				{
					my $fp = File::Spec -> catfile( $d -> contents_path(), $t );

					if( -f $fp )
					{
						$self -> msg( "removing file", $fp );
						assert( unlink( $fp ) );
					} elsif( -d $fp )
					{
						$self -> msg( "removing directory", $fp );
						remove_tree( $fp );
						assert( ( not -d $fp ), 'failed to remove?' );
					} else
					{
						assert( 0, "don't know how to handle " . $fp );
					}
				}
				$need_to_bump_revision = 1;
			}

			foreach my $t ( sort { &fnsrt( $a ) cmp &fnsrt( $b ) } @to_add )
			{
				print $t, "\n";
			}
			
			if( @to_add )
			{
				foreach my $t ( sort { &fnsrt( $a ) cmp &fnsrt( $b ) } @to_add )
				{
					my $fp = File::Spec -> catfile( $d -> config() -> { 'path' }, $t );
					my $fp_ir = File::Spec -> catfile( $d -> contents_path(), $t );

					if( -f $fp )
					{
						$self -> msg( "copying", $t, "into rep" );
						assert( copy( $fp, $fp_ir ), 'could not copy?' );
						assert( -f $fp_ir );
						
					} elsif( -d $fp )
					{
						$self -> msg( "creating dir", $t, "inside rep" );
						assert( mkdir( $fp_ir ), "could not create dir?" );
						assert( -d $fp_ir );
						
					} else
					{
						assert( 0, "don't know how to handle " . $fp );
					}
					$to_update{ $t } = [ 'mtime', 'mode' ];
				}
				$need_to_bump_revision = 1;
			}

			while( my ( $k, $v ) = each %to_update )
			{
				my $fp = File::Spec -> catfile( $d -> contents_path(), $k );
				my $canon = $actual_contents{ $k };

#				print Dumper( $canon );

				foreach my $change ( @{ $v } )
				{
					if( $change eq 'md5' )
					{
						my $fp_or = File::Spec -> catfile( $d -> config() -> { 'path' }, $k ); # outside repo
						my $fp_ir = $fp; # inside repo

						if( -f $fp_ir )
						{
							assert( unlink( $fp_ir ) );
						} elsif( -d $fp_ir )
						{
							assert( remove_tree( $fp_ir ) );
						}
						assert( -f $fp_or );
						copy( $fp_or, $fp_ir );
					}
					
					if( $change eq 'mode' )
					{
						my $newmode = $canon -> { 'mode' };
						$self -> msg( "setting mode", $newmode, "to", $fp );
						assert( chmod( $newmode, $fp ) );
						
					} elsif( ( $change eq 'atime' ) or ( $change eq 'mtime' ) )
					{
						utime( $canon -> { 'atime' },
						       $canon -> { 'mtime' },
						       $fp );
					}
				}
				
				$need_to_bump_revision = 1;
			}

			if( $need_to_bump_revision )
			{
				my $was = $d -> revno();
				my $new = $d -> bump_revno();
				$self -> msg( "revision updated", $was, "->", $new );
			} else
			{
				$self -> msg( "no changes, revision not updated" );
			}
		}
		
	} else
	{
		$self -> msg( "need path to valid Safejunk dir if doing pack" );
	}
	
	return 0;
}

sub action_restore_from_rep
{
	my $self = shift;

	if( my $path = $self -> cmd_line() -> [ 1 ] )
	{
		my $d = SJ::Dir -> new( path => $path );

		if( my $err = $d -> check_errs() )
		{
			$self -> msg( "injalid Safejunk dir", $path, ":", $err );
		} else
		{
			$self -> msg( "path is ok, continuing" );

			my @safe_contents = &SJ::Util::build_tree( $d -> contents_path() );
			$self -> msg( Dumper( \@safe_contents ) );
		}
		
	} else
	{
		$self -> msg( "need path to valid Safejunk dir if doing restore" );
	}
	

	return 0;
}

sub fnsrt
{
	my $str = shift;

	my $rv = sprintf( "%04d%s", length( $str ), $str );
	
	return $rv;
}

sub pack_compare_popout
{
	my ( $self, $safe, $actual ) = @_;

	my @to_remove = ();
	my @to_add = ();
	my %to_update = ();

	my %safe_contents = %{ $safe };
	my %actual_contents = %{ $actual };

	
	{
		foreach my $k ( keys %safe_contents )
		{
			unless( exists $actual_contents{ $k } )
			{
				$self -> msg( $k, "not in actual, remove" );
				push @to_remove, $k;
			}
		}
		
		foreach my $k ( keys %actual_contents )
		{
			unless( exists $safe_contents{ $k } )
			{
				$self -> msg( $k, "not in safe, add" );
				push @to_add, $k;
			}
		}
		
		foreach my $k ( keys %actual_contents )
		{
			if( my $safe = $safe_contents{ $k } )
			{
				if( my $diff = &SJ::Util::compare_two_entries( $actual_contents{ $k },
									       $safe ) )
				{
					$self -> msg( $k, "needs to be updated:", @{ $diff } );
					$to_update{ $k } = $diff;
				}
			}
		}
	}
	
	return ( \@to_remove, \@to_add, \%to_update );
}

__PACKAGE__ -> run( cmd_line => \@ARGV );
