package Plugins::MusicArtistInfo::LFM;

use strict;
use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape uri_escape_utf8);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Text;
use Slim::Utils::Strings qw(string cstring);

use constant BASE_URL => 'http://ws.audioscrobbler.com/2.0/';

my $cache = Slim::Utils::Cache->new;
my $log = logger('plugin.musicartistinfo');
my $aid;

sub init {
	shift->aid(shift->_pluginDataFor('id2'));
}

sub getArtistPhotos {
	my ( $class, $client, $cb, $args ) = @_;

	# last.fm doesn't try to be smart about names: "the beatles" != "beatles" - don't punish users with correct tags
	# this is an ugly hack, but we can't set the ignoredarticles pref, as this triggers a rescan...
	my $ignoredArticles = $Slim::Utils::Text::ignoredArticles;
	%Slim::Utils::Text::caseArticlesCache = ();
	$Slim::Utils::Text::ignoredArticles = qr/^\s+/;

	my $artist = Slim::Utils::Text::ignoreCaseArticles($args->{artist}, 1);

	$Slim::Utils::Text::ignoredArticles = $ignoredArticles;
	
	if (!$artist) {
		$cb->();
		return;
	}

	$cache ||= Slim::Utils::Cache->new;	
	if ( my $cached = $cache->get("lfm_artist_photos_$artist") ) {
		$cb->($cached);
		return;
	}
	
	_call({
		# XXX - artist.getimages has been deprecated by October 2013. getInfo will only return one image :-(
#		method => 'artist.getimages',
		method => 'artist.getInfo',
		artist => $artist,
		autocorrect => 1,
	}, sub {
		my $artistInfo = shift;
		my $result = {};
		
#		if ( $artistInfo && $artistInfo->{images} && (my $images = $artistInfo->{images}->{image}) ) {
		if ( $artistInfo && $artistInfo->{artist} && (my $images = $artistInfo->{artist}->{image}) ) {
			$images = [ $images ] if ref $images eq 'HASH';
			
			if ( ref $images eq 'ARRAY' ) {
#				my @images;
#				foreach my $image (@$images) {
#					my $img;
#					
#					if ($image->{sizes} && $image->{sizes}->{size}) {
#						my $max = 0;
#						
#						foreach ( @{$image->{sizes}->{size}} ) {
#							next if $_->{width} < 250;
#							next if $_->{width} < $max;
#							
#							$max = $_->{width};
#							
#							$img = $_;
#						}
#					}
#					
#					next unless $img;
#					
#					push @images, {
#						author => $image->{owner}->{name} . ' (Last.fm)',
#						url    => $img->{'#text'},
#						height => $img->{height},
#						width  => $img->{width},
#					};
#				}

				my $url = $images->[-1]->{'#text'};
				my ($size) = $url =~ m{/(34|64|126|174|252|500|\d+x\d+)s?/}i;

				my @images = ({
					author => 'Last.fm',
					url    => $url,
					width  => $size * 1 || undef
				});

				if (@images) {
					$result->{photos} = \@images;

					# we keep an aggressive cache of artist pictures - they don't change often, but are often used
					$cache->set("lfm_artist_photos_$artist", $result, 86400 * 30);
				}
			}
		}

		if ( !$result->{photos} && $main::SERVER ) {
			$result->{error} ||= cstring($client, 'PLUGIN_MUSICARTISTINFO_NOT_FOUND');
		}
		
		$cb->($result);
	});
}

# get a single artist picture - wrapper around getArtistPhotos
sub getArtistPhoto {
	my ( $class, $client, $cb, $args ) = @_;

	$class->getArtistPhotos($client, sub {
		my $items = shift || {};

		my $photo;
		if ($items->{error}) {
			$photo = $items;
		}
		elsif ($items->{photos} && scalar @{$items->{photos}}) {
			foreach (@{$items->{photos}}) {
				if ( my $url = $_->{url} ) {
					$photo = $_;
					last;
				}
			}
		}
		
		if (!$photo && $main::SERVER) {
			$photo = {
				error => cstring($client, 'PLUGIN_MUSICARTISTINFO_NOT_FOUND')
			};
		}

		$cb->($photo);
	},
	$args );
}

sub getAlbumCover {
	my ( $class, $client, $cb, $args ) = @_;

	my $key = "mai_lfm_albumcover_" . Slim::Utils::Text::ignoreCaseArticles($args->{artist} . $args->{album}, 1);
	
	if (my $cached = $cache->get($key)) {
		$cb->($cached);
		return;
	}

	$class->getAlbumCovers($client, sub {
		my $covers = shift;
		
		my $cover = {};

		# XXX - can we be smarter than return the first image?		
		if ($covers && $covers->{images} && ref $covers->{images} eq 'ARRAY') {
			$cover = $covers->{images}->[0];
		}
		
		$cache->set($key, $cover, 86400);
		$cb->($cover);
	}, $args);	
}

sub getAlbumCovers {
	my ( $class, $client, $cb, $args ) = @_;
	
	$class->getAlbum(sub {
		my $albumInfo = shift;
		my $result = {};
		
		if ( $albumInfo && $albumInfo->{album} && (my $image = $albumInfo->{album}->{image}) ) {
			$image = [ $image ] if ref $image eq 'HASH';

			if ( ref $image eq 'ARRAY' ) {
				$result->{images} = [ reverse grep {
					$_
				} map {
					my ($size) = $_->{'#text'} =~ m{/(34|64|126|174|252|500|\d+x\d+)s?/}i;
					
					# ignore sizes smaller than 300px
					{
						author => 'Last.fm',
						url    => $_->{'#text'},
						width  => $size || $_->{size},
					} if $_->{'#text'} && (!$size || $size*1 >= 300);
				} @{$image} ];
				
				delete $result->{images} unless scalar @{$result->{images}};
			}
		}

		if ( !$result->{images} && !main::SCANNER ) {
			$result->{error} ||= cstring($client, 'PLUGIN_MUSICARTISTINFO_NOT_FOUND');
		}
		
		$cb->($result);
	}, $args);
}

sub getAlbum {
	my ( $class, $cb, $args ) = @_;

	# last.fm doesn't try to be smart about names: "the beatles" != "beatles" - don't punish users with correct tags
	# this is an ugly hack, but we can't set the ignoredarticles pref, as this triggers a rescan...
	my $ignoredArticles = $Slim::Utils::Text::ignoredArticles;
	%Slim::Utils::Text::caseArticlesCache = ();
	$Slim::Utils::Text::ignoredArticles = qr/^\s+/;

	my $artist = Slim::Utils::Text::ignoreCaseArticles($args->{artist}, 1);
	my $album  = Slim::Utils::Text::ignoreCaseArticles($args->{album}, 1);

	$Slim::Utils::Text::ignoredArticles = $ignoredArticles;
	
	if (!$artist || !$album) {
		$cb->();
		return;
	}

	_call({
		method => 'album.getinfo',
		artist => $artist,
		album  => $album,
		autocorrect => 1,
	}, sub {
		$cb->(shift);
	});
}

sub _call {
	my ( $args, $cb ) = @_;
	
	my @query;
	while (my ($k, $v) = each %$args) {
		next if $k =~ /^_/;		# ignore keys starting with an underscore
		
		if (ref $v eq 'ARRAY') {
			foreach (@$v) {
				push @query, $k . '=' . uri_escape_utf8($_);
			}
		}
		else {
			push @query, $k . '=' . uri_escape_utf8($v);
		}
	}
	push @query, 'api_key=' . aid(), 'format=json';

	my $params = join('&', @query);
	my $url = BASE_URL;

	my $cb2 = sub {
		my $response = shift;
		
		main::DEBUGLOG && $log->is_debug && $response->code !~ /2\d\d/ && $log->debug(_debug(Data::Dump::dump($response, @_)));
		my $result = eval { from_json( $response->content ) };
	
		$result ||= {};
		
		if ($@) {
			 $log->error($@);
			 $result->{error} = $@;
		}

		main::DEBUGLOG && $log->is_debug && warn Data::Dump::dump($result);
			
		$cb->($result);
	};
	
	Plugins::MusicArtistInfo::Common->call($url . '?' . $params, $cb2, {
		cache => 1
	});
}

sub _debug {
	my $msg = shift;
	$msg =~ s/$aid/\*/gi if $aid;
	return $msg;
}

sub aid {
	if ( $_[1] ) {
		$aid = $_[1];
		$aid =~ s/-//g;
		$cache->set('lfm_aid', $aid, 'never');
	}
	
	$aid ||= $cache->get('lfm_aid');

	return $aid; 
}

1;