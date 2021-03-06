use strict;
use warnings;

package SJ::App;
use Moose;

our $VERSION = '0.001';

sub run
{
	my $self = shift;

	unless( ref( $self ) )
	{
		# class name call, no prob, we'll create an object for you, pal
		return $self -> new( @_ ) -> run();
	}

	{
		my $init_res = undef;

		eval
		{
			$init_res = $self -> init();
			
		};
		# catch( EjectException $e )
		if( my $e = $@ )
		{
			if( ref( $e ) and blessed( $e ) and $e -> isa( 'EjectException' ) )
			{
				$init_res = $e -> rv();
			} else
			{
				die $e;
			}
		}

	
		if( my $t = $init_res )
		{
			my $rv = $t;
			
			unless( ref( $rv ) )
			{
				$rv = $self -> error( 'init', $rv );
			}
			
			$self -> cleanup();
			
			return $rv;

		}
	}

	my $mode = 'default';

	my $mode_method = 'app_mode_' . $mode;

	
	if( my $t = $self -> always() )
	{

		my $rv = $t;

		unless( ref( $rv ) )
		{
			$rv = $self -> error( 'always', $rv );
		}

		$self -> cleanup();
		
		return $rv;

	}

	my $rv = undef;


	eval
	{
		$rv = $self -> $mode_method();

	};
	# catch( EjectException $e )
	if( my $e = $@ )
	{
		if( ref( $e ) and blessed( $e ) and $e -> isa( 'EjectException' ) )
		{
			$rv = $e -> rv();
		} else
		{
			die $e;
		}
	}

	$self -> cleanup();

	return $rv;
}

sub eject
{
	my ( $self, $rv ) = @_;

	unless( ref( $rv ) )
	{
		$rv = $self -> nctd( $rv );
	}

	die EjectException -> new( rv => $rv );
}

sub app_mode_default
{
	my $self = shift;

	return $self -> ncd( 'Default app mode. Redefine this method in your application.' );
}

sub always
{
	# something that should always be done, called after init
	# if returns error code, error() called
	my $self = shift;

	return 0;
}

sub init
{
	# app initialization, called first
	# if returns error code, error() called
	my $self = shift;
	
	return 0;
}

sub cleanup
{
	my $self = shift;
	return 0;
}

sub error
{
	my $self = shift;

	my ( $from, $code ) = @_;

	if( ref( $code ) eq 'EjectException' )
	{
		return $code -> rv();

	} elsif( ref( $code ) ) # that is output returned, pass as is
	{
		return $code;
	} 

	return $self -> nctd( sprintf( '(SJ::App) Application error default handler (%s, %s)', $from, $code ) );
}

package EjectException;

use Moose;

has 'rv' => ( is => 'rw', isa => 'HashRef' );

1;
