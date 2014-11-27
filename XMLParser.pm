package Plugins::MusicArtistInfo::XMLParser;

use strict;
use File::Slurp;
use XML::Simple;

use Slim::Utils::Log;

my $types = {
	review    => 'textarea',
	biography => 'textarea',
	thumb     => 'image',
};

my $log = logger('plugin.musicartistinfo');

sub parseNFO {
	my ($class, $path) = @_;

	my $content = File::Slurp::read_file($path);
	$content = Slim::Utils::Unicode::utf8decode($content);
	
	# some cleanup, because XBMC's documentation gives invalid XML sample code...
	$content =~ s/ clear=\w+?>/>/sig;
	
	my $items = [];
	my $title;
	my $xml = eval{ XMLin($content) };
	
	# if we fail to parse, then 
	if ($@) {
		$log->error($@);
		
		return {
			title => $path,
			items => [{
				type  => 'preformatted',
				value => $content,
			}],
		};
	}

	foreach my $x ( qw(artist review biography thumb instruments genre style mood theme releasedate year label type rating born formed died disbanded) ) {
		if ( $xml->{$x} ) {
			if ( $x eq 'thumb' ) {
				foreach my $thumb ( @{$xml->{$x}} ) {
					push @$items, {
						type => 'image',
						url  => $thumb
					} if $thumb =~ /^http/;
				}
			}
			else {
				my $v = $xml->{$x};
				if ( ref $v ) {
					next if ref $v ne 'ARRAY';
					$v = join(', ', map { Slim::Utils::Unicode::utf8encode($_) } @$v);
				}
				else {
					$v = Slim::Utils::Unicode::utf8encode($xml->{$x});
				}
				
				push @$items, {
					title => Slim::Utils::Unicode::utf8encode(ucfirst($x)),
					value => $v,
					type  => $types->{$x} || '',
				};
			}
		}
	}

	return {
		title => $xml->{name} || $xml->{title},
		items => $items,
	};
}

sub renderNFO {
	my ($class, $httpClient, $response, $path) = @_;

	my $data = $class->parseNFO($path);

	$response->content_type('text/html');
	$response->header('Connection' => 'close');
	$response->content_ref(Slim::Web::HTTP::filltemplatefile('/plugins/MusicArtistInfo/nfo.html', {
		title => $data->{title},
		webroot => '/',
		path => $response->request->uri->path,
		items => $data->{items},
	}));

	$httpClient->send_response($response);
	Slim::Web::HTTP::closeHTTPSocket($httpClient);
	return;
}

1;