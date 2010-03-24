use inc::Module::Install;


name 'SNAG';
all_from 'lib/SNAG.pm';
 
requires(
  'Crypt::CBC' => 0,
  'Crypt::Blowfish' => 0,
  'Crypt::Rijndael' => 0,
  'DBI' => 0,
  'DBM::Deep' => 0,
  'Data::Dumper' => 0,
  'Date::Manip' => 0,
  'Date::Parse' => 0,
  'Devel::Size' => 0,
  'Digest::SHA qw(sha256_hex)' => 0,
  'FreezeThaw qw(thaw freeze cmpStr cmpStrHard)' => 0,
  'HTML::Entities' => 0,
  'Mail::Sendmail' => 0,
  'Net::Nslookup' => 0,
  'POE::Component::Client::TCP' => 0,
  'POE::Component::EasyDBI' => 0,
  'POE::Component::Server::TCP' => 0,
  'POE::Filter::Line' => 0,
  'POE::Filter::Reference' => 0,
  'POE::Session' => 0,
  'POE::Wheel::Run' => 0,
  'POE' => 0,
  'Proc::ProcessTable' => 0,
  'RRDTool::OO' => 0,
  'RRDs' => 0,
  'Socket' => 0,
  'Statistics::Descriptive' => 0,
  'Storable qw/dclone store retrieve/' => 0,
  'Text::Diff' => 0,
  'URI::Escape' => 0,
  'XML::Simple' => 0,
  'version' => 0,
);
 
auto_install; 
WriteAll;
