use strict;
use warnings;

package SJ::Msg;
use Moose::Role;

has 'debug_mode' => ( is => 'rw', isa => 'Bool', default => 1 ); 

sub log_timestamp
{
        my $self = shift;

        my @t = localtime( time() );

        return sprintf( "[%04d-%02d-%02d %02d:%02d:%02d][%05d]",
			$t[ 5 ] + 1900,
			$t[ 4 ] + 1,
			@t[ 3, 2, 1, 0 ],
			$$  );

}

sub form_msg
{
        my $self = shift;

	my $msg = $self -> log_timestamp() . " " . join( " ", @_ ) . "\n";

	return $msg;
}

sub msg
{
	my $self = shift;

	my ( $will_print, $method ) = ( 0, 'debug_mode' );

	if( $self -> can( $method ) )
	{
		$will_print = $self -> $method();
	}
	
	if( $will_print )
	{
		print $self -> form_msg( @_ );
	}

	return 0;
}


1;
