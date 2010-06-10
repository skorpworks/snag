use ExtUtils::MakeMaker;

push @extra, 'INSTALLDIRS' => 'perl' if $] >= 5.008009;

WriteMakefile
(
    'NAME' => 'SNAG',
    'VERSION_FROM' => 'lib/SNAG.pm',
    'ABSTRACT_FROM' => 'lib/SNAG.pm',
    'PREREQ_PM' => {
		'Capture::Tiny' => 0,
	  'Config::General' => 0,
	  'Crypt::CBC' => 0,
	  'Crypt::Blowfish' => 0,
	  'Crypt::Rijndael' => 0,
	  'DBI' => 0,
	  'DBM::Deep' => 0,
	  'Data::Dumper' => 0,
	  'Date::Parse' => 0,
	  'Devel::Size' => 0,
	  'Digest::SHA' => 0,
	  'FreezeThaw' => 0,
	  'HTML::Entities' => 0,
	  'LWP' => 0,
	  'Mail::Sendmail' => 0,
	  'Net::Nslookup' => 0,
	  'POE::Component::EasyDBI' => 0,
	  'POE::XS::Loop::Poll' => 0,
	  'POE' => 0,
	  'Proc::ProcessTable' => 0,
	  'Statistics::Descriptive' => 0,
	  'Storable' => 0,
	  'Text::Diff' => 0,
	  'URI::Escape' => 0,
	  'version' => 0,
    },
    'EXE_FILES' => [ 'script/snagw.pl', 'script/snagp.pl', 'script/snags.pl', 'script/snagc.pl' ],
    'PL_FILES' => {},
    LICENSE => 'perl',
    @extra,
);
