package Autosell::API::CoinEx;

use parent 'Autosell::API::Exchange';

use warnings;
use strict;
use Exporter;

# dependencies
use JSON qw( decode_json ); # JSON decode
use Try::Tiny; # error handling

# logger
my $log;

####################################################################################################
# Initialize Exchange
# 
# Params:
#  name: name of exchange
#  key: API key for exchange
#  secret: API secret
#
# Returns self
####################################################################################################
sub new
{
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $self->_init( @_ );
    return $self;
}

####################################################################################################
# Initialize Exchange
# 
# Params:
#  name: name of exchange
#  key: API key for exchange
#  secret: API secret
#
####################################################################################################
sub _init
{
    my $self = shift;
    $self->SUPER::_init( @_ );
    
    $self->{ url } = 'https://coinex.pw/api/v2/'; # API URL
    
    # set headers
    $self->{ ua }->default_header(
        'Content-type' => 'application/json',
        'Accept' => 'application/json',
        'User-Agent' => 'altcoin-autoseller-perl',
        'API-Key' => $self->{ key });
    
    $log = Log::Log4perl->get_logger( __PACKAGE__ );
}

####################################################################################################
# Get all available currencies on exchange
# 
# Params:
#  excludes: array of coins to exclude(by name)
# 
# Returns hashref of currency ID => name
####################################################################################################
sub currencies
{
    my $self = shift;
    my @tempExcludes = shift;
    my %excludes;
    @excludes{ @tempExcludes }=();
    
    # build hashref of currencies
    $log->debug( "Querying $self->{ name } for currencies..." );
    try
    {
        my $currencies = {};
        my $response = $self->_request( 'currencies' );
        for my $currency ( @$response )
        {
        	$currencies->{ $currency->{ id } } = $currency->{ name }
        	   unless ( exists $excludes{ uc( $currency->{ name } ) } ||
        	   $currency->{ name } eq 'SwitchPool-scrypt' || # why are these currencies?
        	   $currency->{ name } eq 'SwitchPool-sha256' );
        }
        
        return $currencies;
    }
    catch
    {
    	$log->error( "Error: $_" );
    	$log->error_die( "Unable to get currencies from $self->{ name }!" );
    };
}

####################################################################################################
# Send API request
# 
# Params:
#  call: Method/API call
#  post: hashref of post data(optional)
# 
# Returns response
####################################################################################################
sub _request
{
    my $self = shift;
    my $call = shift;
    my $post = shift || undef;
    
    # form request
    my $request = undef;
    if ( defined $post )
    {
        my $post = encode_json $post
        $self->{ ua }->default_header( 'API-Sign' => hmac_sha512( $post , $self->{ secret } )); # sign data
        $request = HTTP::Request->new( 'POST' , $self->{ url } . $call , $self->{ ua }->default_headers , $post);
    }
    else
    {
        $self->{ ua }->default_header( 'API-Sign' => ''); # clear sign data
        $request = HTTP::Request->new( 'GET' , $self->{ url } . $call , $self->{ ua }->default_headers );
    }
    
    # perform request and get response
    my $response = $self->{ ua }->request( $request );
    
    # success
    if ( $response->is_success )
    {
    	my $json = decode_json( $response->decoded_content );
    	
    	# ensure we got data we care about
    	unless ( $json->{ $call } )
    	{
            $log->error( "$self->{ name } error on request: '$self->{ url }$call'." );
            $log->error( "Invalid response! Bad data." );
    		die "Invalid response! Bad data.";
    	}
    	return $json->{ $call }
    }
    else
    {
    	$log->error( "$self->{ name } error on request: '$self->{ url }$call'." );
    	$log->error( $response->error_as_HTML );
    	die "Request error!"; # error out
    }
}

1;