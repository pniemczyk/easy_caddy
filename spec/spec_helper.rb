# frozen_string_literal: true

require 'tmpdir'

# Point ecaddy at a temp dir for every spec so real ~/.config/caddy is never touched.
RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    @ecaddy_home = Dir.mktmpdir('ecaddy_test')
    ENV['ECADDY_HOME'] = @ecaddy_home
  end

  config.after(:each) do
    FileUtils.remove_entry(@ecaddy_home)
    ENV.delete('ECADDY_HOME')
  end
end

require 'easy_caddy'
