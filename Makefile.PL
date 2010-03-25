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
  'Date::Parse' => 0,
  'Devel::Size' => 0,
  'Digest::SHA' => 0,
  'FreezeThaw' => 0,
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
  'Socket' => 0,
  'Statistics::Descriptive' => 0,
  'Storable' => 0,
  'Text::Diff' => 0,
  'URI::Escape' => 0,
  'XML::Simple' => 0,
  'version' => 0,
);

feature 'RRD Server', 'RRDs' => 0;
feature 'RRD Server', 'RRDTool::OO' => 0;

install_script glob('script/*.pl');
auto_install; 
WriteAll;
