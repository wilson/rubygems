#--
# Copyright 2006, 2007 by Chad Fowler, Rich Kilmer, Jim Weirich, Eric Hodel
# and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

$:.unshift 'lib'
require 'rubygems'

require 'fileutils'
require 'rbconfig'
require 'rdoc/rdoc'
require 'tmpdir'

include FileUtils::Verbose

# check ruby version

required_version = Gem::Version::Requirement.create(">= 1.8.2")

unless required_version.satisfied_by? Gem::Version.new(RUBY_VERSION) then
  abort "Expected Ruby version #{required_version}, was #{RUBY_VERSION}"
end

# install stuff

lib_dir = nil
bin_dir = nil

if ARGV.grep(/^--prefix/).empty? then
  lib_dir = Config::CONFIG['sitelibdir']
  bin_dir = Config::CONFIG['bindir']
else
  prefix = nil

  ARGV.grep(/^--prefix=(.*)/)
  if $1.nil? or $1.empty? then
    path_index = ARGV.index '--prefix'
    prefix = ARGV[path_index + 1]
  else
    prefix = $1
  end

  raise "invalid --prefix #{prefix.inspect}" if prefix.nil?

  lib_dir = File.join prefix, 'lib'
  bin_dir = File.join prefix, 'bin'

  mkdir_p lib_dir
  mkdir_p bin_dir
end

Dir.chdir 'lib' do
  lib_files = Dir[File.join('**', '*rb')]

  lib_files.each do |lib_file|
    dest_file = File.join lib_dir, lib_file
    dest_dir = File.dirname dest_file
    mkdir_p dest_dir unless File.directory? dest_dir

    install lib_file, dest_file, :mode => 0644
  end
end

Dir.chdir 'bin' do
  bin_files = Dir['*']

  bin_files.each do |bin_file|
    dest_file = File.join bin_dir, bin_file
    bin_tmp_file = File.join Dir.tmpdir, bin_file

    begin
      cp bin_file, bin_tmp_file
      bin = File.readlines bin_tmp_file
      bin[0] = "#!#{Gem.ruby}\n"

      File.open bin_tmp_file, 'w' do |fp|
        fp.puts bin.join
      end

      install bin_tmp_file, dest_file, :mode => 0755
    ensure
      rm bin_tmp_file
    end

    next unless Gem.win_platform?

    begin
      bin_cmd_file = File.join Dir.tmpdir, "#{bin_file}.cmd"

      File.open bin_cmd_file, 'w' do |file|
        file.puts %{@"#{Gem.ruby}" "#{bin_file}" %1 %2 %3 %4 %5 %6 %7 %8 %9}
      end

      install bin_cmd_file, "#{dest_file}.cmd", :mode => 0755
    ensure
      rm bin_cmd_file
    end
  end
end

# Remove source caches

require 'rubygems/source_info_cache'

user_cache_file = Gem::SourceInfoCache.user_cache_file
system_cache_file = Gem::SourceInfoCache.system_cache_file

rm user_cache_file if File.writable? user_cache_file
rm system_cache_file if File.writable? system_cache_file

# install RDoc

gem_doc_dir = File.join Gem.dir, 'doc'

if File.writable? gem_doc_dir then
  puts "Removing old RubyGems RDoc and ri..."
  Dir[File.join(Gem.dir, 'doc', 'rubygems-[0-9]*')].each do |dir|
    rm_rf dir
  end

  def run_rdoc(*args)
    args << '--quiet'
    args << '--main' << 'README'
    args << '.' << 'README' << 'LICENSE.txt' << 'GPL.txt'

    r = RDoc::RDoc.new
    r.document args
  end

  rubygems_name = "rubygems-#{Gem::RubyGemsVersion}"

  doc_dir = File.join Gem.dir, 'doc', rubygems_name

  unless ARGV.include? '--no-ri' then
    ri_dir = File.join doc_dir, 'ri'
    puts "Installing #{rubygems_name} ri into #{ri_dir}..."
    run_rdoc '--ri', '--op', ri_dir
  end

  unless ARGV.include? '--no-rdoc' then
    rdoc_dir = File.join(doc_dir, 'rdoc')
    puts "Installing #{rubygems_name} rdoc into #{rdoc_dir}..."
    run_rdoc '--op', rdoc_dir
  end
else
  puts "Skipping RDoc generation, #{gem_doc_dir} not writable"
  puts "Set the GEM_HOME environment variable if you want RDoc generated"
end

# Remove stubs

def stub?(path)
  return unless File.readable? path
  File.read(path, 40) =~ /^# This file was generated by RubyGems/ and
  File.readlines(path).size < 20
end

puts <<-EOF.gsub(/^ */, '')
  As of RubyGems 0.8.0, library stubs are no longer needed.
  Searching $LOAD_PATH for stubs to optionally delete (may take a while)...
  EOF

gemfiles = Dir[File.join("{#{($LOAD_PATH).join(',')}}", '**', '*.rb')]
gemfiles = gemfiles.map { |file| File.expand_path file }.uniq

puts "...done."

seen_stub = false

gemfiles.each do |file|
  next if File.directory? file
  next unless stub? file

  unless seen_stub then
    puts "\nRubyGems has detected stubs that can be removed.  Confirm their removal:"
  end
  seen_stub = true

  print "  * remove #{file}? [y/n] "
  answer = gets

  if answer =~ /y/i then
    unlink file
    puts "        (removed)"
  else
    puts "        (skipping)"
  end
end

if seen_stub then
  puts "Finished with library stubs."
else
  puts "No library stubs found."
end

