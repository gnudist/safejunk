#!/usr/bin/perl

use strict;
use warnings;

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

sub app_mode_default
{
	my $self = shift;

	$self -> msg( "Safejunk ver.", $self -> version(), "starting" );

	if( my $action = $self -> cmd_line() -> [ 0 ] )
	{
		if( $action eq 'pack' )
		{
			$self -> action_pack();
			
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
sub action_pack
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

			my ( $to_remove, $to_add, $to_update ) = $self -> pack_compare_popout( \%safe_contents, \%actual_contents );
			
			my @to_remove = @{ $to_remove };
			my @to_add = @{ $to_add };
			my %to_update = %{ $to_update };
			my $need_to_bump_revision = 0;

			if( @to_remove )
			{
				# TODO
				foreach my $t ( sort { &fnsrt( $b ) cmp &fnsrt( $a ) } @to_remove )
				{
					print $t, "\n";
				}
			}

			

			

			
			
		}
		
	} else
	{
		$self -> msg( "need path to valid Safejunk dir if doing pack" );
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
