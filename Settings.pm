package Plugins::MusicArtistInfo::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
my $CAN_IMAGEPROXY;

my $prefs = preferences('plugin.musicartistinfo');

sub new {
	(my $class, $CAN_IMAGEPROXY) = @_;
	$class->SUPER::new();
}

sub name {
	return 'PLUGIN_MUSICARTISTINFO';
}

sub prefs {
	return ($prefs, 'browseArtistPictures', 'runImporter', 'lookupArtistPictures', 'artistImageFolder', 'saveArtistPictures');
}

sub page {
	return 'plugins/MusicArtistInfo/settings.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;
	
	# disable saving to image folder if it isn't writeable
	my $imageFolder = $paramRef->{pref_artistImageFolder} || $prefs->get('artistImageFolder');
	
	if ( !($imageFolder && -d $imageFolder && -w $imageFolder) ) {
		$paramRef->{savePicturesDisabled} = 1;
	}
	
	$paramRef->{limited} = !$CAN_IMAGEPROXY;
	
	$class->SUPER::handler($client, $paramRef, $pageSetup)
}

1;