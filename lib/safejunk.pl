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
use Cwd 'getcwd';

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
		} elsif( $action eq 'pack' )
		{
			$self -> action_pack_rep();
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

sub action_pack_rep
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
			my $orig = getcwd();
			assert( chdir( $path ) );

			$self -> msg( "invoking external pack command" );
			my $rc = &SJ::Util::exec_cmd( &SJ::Util::tar_exe(),
						      '-cz',
						      './' );
			$self -> msg( "external pack command finished" );

			if( $rc -> { 'rc' } == 0 )
			{
				unlink( $rc -> { 'err' } );

				assert( -f ( my $packed = $rc -> { 'out' } ) );
				$self -> msg( "... successfully packed into", $packed );

				my $encrypted = File::Temp::tmpnam();

				$self -> msg( "encypting..." );
				my $erc = &SJ::Util::exec_cmd( &SJ::Util::gpg_exe(),
							       "--output",
							       $encrypted,
							       "--encrypt",
							       "--sign",
							       "--recipient",
							       $d -> config() -> { 'gpg_key_id' },
							       $packed );
				assert( unlink( $packed ) );
				$self -> msg( "finished" );

				if( $erc -> { 'rc' } == 0 )
				{
					$self -> msg( "encrypted in", $encrypted );

					# TODO handle push
					
				} else
				{
					assert( 0, &SJ::Util::slurp( $erc -> { 'err' } ) .
						   Dumper( $erc ) );
				}
				
				
				
				
			} else
			{
				assert( 0, &SJ::Util::slurp( $rc -> { 'err' } ) .
					   Dumper( $rc ) );
			}
			
			assert( chdir( $orig ) );
		}
	} else
	{
		$self -> msg( "need path to valid Safejunk dir if doing pack" );
	}

	return 0;
	
}

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

			my %safe_contents = %{ $self -> popout_contents_build( $d -> contents_path() ) };

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
		$self -> msg( "need path to valid Safejunk dir if doing rep update" );
	}
	
	return 0;
}

sub popout_contents_build
{
	my ( $self, $path ) = @_;

	my %safe_contents = ();
	
	{
		my @safe_contents = &SJ::Util::build_tree( $path );
		
		my $remove = $path;
		
		foreach my $f ( @safe_contents )
		{
			my @t = %{ $f };
			assert( scalar @t == 2 );
			
			$t[ 0 ] =~ s/\Q$remove\E//g;
			$t[ 0 ] =~ s/^[\/\\]//;
			
			$safe_contents{ $t[ 0 ] } = $t[ 1 ];
		}
	}
	
	return \%safe_contents;
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

			my %safe_contents = %{ $self -> popout_contents_build( $d -> contents_path() ) };

			my %actual_contents = ();

			foreach my $e ( keys %safe_contents )
			{
				my @t = $d -> managed_entry_from_outside( $e, { only_dir => 1,
										missing_ok => 1 } );

				foreach my $t ( @t )
				{
					my @t1 = %{ $t };
					assert( scalar @t1 == 2 );
					$actual_contents{ $t1[ 0 ] } = $t1[ 1 ];
				}
			}

			# my %me_contents = ();

			# foreach my $e ( @{ $d -> managed_entries() } )
			# {
			# 	my @t = $d -> managed_entry_from_outside( $e, { only_dir => 1,
			# 							missing_ok => 1 } );

			# 	foreach my $t ( @t )
			# 	{
			# 		my @t1 = %{ $t };
			# 		assert( scalar @t1 == 2 );
			# 		$me_contents{ $t1[ 0 ] } = $t1[ 1 ];
			# 	}
			# }
			

			
			# print Dumper( \%me_contents );
			# print "--------------------\n";
			# print Dumper( \%actual_contents );

			# my ( $to_remove, $to_add, $to_update ) = $self -> pack_compare_popout( \%actual_contents, \%me_contents );
			# $self -> msg( "remove:", Dumper( $to_remove ) );
			
			my ( $to_remove, $to_add, $to_update ) = $self -> pack_compare_popout( \%actual_contents, \%safe_contents );

			# TODO: remove anything at all?

			# $self -> msg( "remove:", Dumper( $to_remove ) );
			# $self -> msg( "add:", Dumper( $to_add ) );
			# $self -> msg( "update:", Dumper( $to_update ) );

			my @to_add = @{ $to_add };
			my %to_update = %{ $to_update };


			if( @to_add )
			{
				foreach my $t ( sort { &fnsrt( $a ) cmp &fnsrt( $b ) } @to_add )
				{
					my $fp_or = File::Spec -> catfile( $d -> config() -> { 'path' }, $t );
					my $fp_ir = File::Spec -> catfile( $d -> contents_path(), $t );

					if( -f $fp_ir )
					{
						$self -> msg( "copying", $t, "from rep" );
						assert( copy( $fp_ir, $fp_or ), 'could not copy?' );
						assert( -f $fp_or );
						
					} elsif( -d $fp_ir )
					{
						$self -> msg( "creating dir", $t );
						assert( mkdir( $fp_or ), "could not create dir?" );
						assert( -d $fp_or );
						
					} else
					{
						assert( 0, "don't know how to handle " . $fp_ir );
					}
					$to_update{ $t } = [ 'mtime', 'mode' ];
				}
			}

			while( my ( $k, $v ) = each %to_update )
			{
				my $fp_or = File::Spec -> catfile( $d -> config() -> { 'path' }, $k );
				my $fp_ir = File::Spec -> catfile( $d -> contents_path(), $k );
				assert( my $canon = $safe_contents{ $k } );

				foreach my $change ( sort @{ $v } )
				{
					if( $change eq 'md5' )
					{
						if( -f $fp_or )
						{
							assert( unlink( $fp_or ), "remove " . $fp_or );
						} elsif( -d $fp_or )
						{
							assert( 0 );
						}
						assert( -f $fp_ir );
						copy( $fp_ir, $fp_or );
					}
					
					if( $change eq 'mode' )
					{
						my $newmode = $canon -> { 'mode' };
						$self -> msg( "setting mode", $newmode, "to", $fp_or );
						assert( chmod( $newmode, $fp_or ) );
						
					} elsif( ( $change eq 'atime' ) or ( $change eq 'mtime' ) )
					{
						utime( $canon -> { 'atime' },
						       $canon -> { 'mtime' },
						       $fp_or );
					}
				}
			}

			$self -> msg( "completed" );
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
