require 'json'

# Utility methods used for versioning projects for various kinds of packaging
module Pkg::Util::Version
  class << self

    def uname_r
      uname = Pkg::Util::Tool.find_tool('uname', :required => true)
      stdout, _, _ = Pkg::Util::Execution.capture3("#{uname} -r")
      stdout.chomp
    end

    def get_ips_version
      if info = Pkg::Config.version
        version, commits, dirty = info
        if commits.to_s.match('^rc[\d]+')
          commits = info[2]
          dirty   = info[3]
        end
        osrelease = uname_r
        "#{version},#{osrelease}-#{commits.to_i}#{dirty ? '-dirty' : ''}"
      else
        get_pwd_version
      end
    end

    def get_pwd_version
      Dir.pwd.split('.')[-1]
    end

    def get_debversion
      base_pkg_version.join('-') << "#{Pkg::Config.packager}1"
    end

    def get_origversion
      Pkg::Config.debversion.split('-')[0]
    end

    def get_rpmversion
      base_pkg_version[0]
    end

    def get_rpmrelease
      base_pkg_version[1]
    end

    # This is used to set Pkg::Config.version
    def dash_version
      Pkg::Util::Git.describe
    end

    # This version is used for gems and platform types that do not support
    # dashes in the package version
    def dot_version(version = Pkg::Config.version)
      version.tr('-', '.')
    end

    # We need to figure out what we use this for an if we can consolidate it
    # 4.99.0.22.gf64bc49-1
    # 4.4.1-0.1SNAPSHOT.2017.05.16T1005
    # 4.99.0-1
    # 4.99.0.29.g431768c-1
    # 2.7.1-1
    # 5.3.0.rc4-1
    # 3.0.5.rc6.24.g431768c-1
    #
    # Given a version, reformat it to be appropriate for a final package
    # version. This means we need to add a `0.` before the release version
    # for non-final builds
    #
    # This only applies to packages that are built with the automation in this
    # repo. This is invalid for all other build automation, like vanagon
    #
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def base_pkg_version(version = Pkg::Config.version)
      return "#{dot_version(version)}-#{Pkg::Config.release}".split('-') if final?(version) || Pkg::Config.vanagon_project

      if version.include?('SNAPSHOT')
        new_version = dot_version(version).sub(/\.SNAPSHOT/, "-0.#{Pkg::Config.release}SNAPSHOT")
      elsif version.include?('rc')
        rc_ver = dot_version(version).match(/\.?rc(\d+)/)[1]
        new_version = dot_version(version).sub(/\.?rc(\d+)/, '') + "-0.#{Pkg::Config.release}rc#{rc_ver}"
      else
        new_version = dot_version(version) + "-0.#{Pkg::Config.release}"
      end

      if new_version.include?('dirty')
        new_version = new_version.sub(/\.?dirty/, '') + 'dirty'
      end

      new_version.split('-')
    end

    # Determines if the version we are working with is or is not final
    #
    # The version here does not include the release version. Therefore, we
    # assume that any version that includes a `-\d+` was not built from a tag
    # and is a non-final version.
    # Examples:
    # Final
    #   - 5.0.0
    #   - 2016.5.6.7
    # Nonfinal
    #   - 4.99.0-22
    #   - 1.0.0-658-gabc1234
    #   - 5.0.0.master.SNAPSHOT.2017.05.16T1357
    #   - 5.9.7-rc4
    #   - 4.99.0-56-dirty
    #
    def final?(version = Pkg::Config.version)
      case version
      when /rc/, /SNAPSHOT/, /-dirty/
        false
      when /g[a-f0-9]{7}$/, /^(\d+\.)+\d+-\d+$/
        false
      when /^(\d+\.)+\d+$/
        true
      else
        true
      end
    end

    # This is to support packages that only burn-in the version number in the
    # release artifact, rather than storing it two (or more) times in the
    # version control system.  Razor is a good example of that; see
    # https://github.com/puppetlabs/Razor/blob/master/lib/project_razor/version.rb
    # for an example of that this looks like.
    #
    # If you invoke this the version will only be modified in the temporary copy,
    # with the intent that it never change the official source tree.
    #
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def versionbump(workdir = nil)
      version = ENV['VERSION'] || Pkg::Config.version.to_s.strip
      new_version = '"' + version + '"'

      version_file = "#{workdir ? workdir + '/' : ''}#{Pkg::Config.version_file}"

      # Read the previous version file in...
      contents = IO.read(version_file)

      # Match version files containing 'VERSION = "x.x.x"' and just x.x.x
      if contents =~ /VERSION =.*/
        old_version = contents.match(/VERSION =.*/).to_s.split[-1]
      else
        old_version = contents
      end

      puts "Updating #{old_version} to #{new_version} in #{version_file}"
      if contents =~ /@DEVELOPMENT_VERSION@/
        contents.gsub!('@DEVELOPMENT_VERSION@', version)
      elsif contents =~ /version\s*=\s*[\'"]DEVELOPMENT[\'"]/
        contents.gsub!(/version\s*=\s*['"]DEVELOPMENT['"]/, "version = '#{version}'")
      elsif contents =~ /VERSION = #{old_version}/
        contents.gsub!("VERSION = #{old_version}", "VERSION = #{new_version}")
      elsif contents =~ /#{Pkg::Config.project.upcase}VERSION = #{old_version}/
        contents.gsub!("#{Pkg::Config.project.upcase}VERSION = #{old_version}", "#{Pkg::Config.project.upcase}VERSION = #{new_version}")
      else
        contents.gsub!(old_version, Pkg::Config.version)
      end

      # ...and write it back on out.
      File.open(version_file, 'w') { |f| f.write contents }
    end

    # Human readable output for json tags reporting. This will load the
    # input json file and output if it "looks tagged" or not
    #
    # @param json_data [hash] json data hash containing the ref to check
    def report_json_tags(json_data) # rubocop:disable Metrics/AbcSize
      puts 'component: ' + File.basename(json_data['url'])
      puts 'ref: ' + json_data['ref'].to_s
      if Pkg::Util::Git.remote_tagged?(json_data['url'], json_data['ref'].to_s)
        tagged = 'Tagged? [ Yes ]'
      else
        tagged = 'Tagged? [ No  ]'
      end
      col_len = (ENV['COLUMNS'] || 70).to_i
      puts format("\n%#{col_len}s\n\n", tagged)
      puts '*' * col_len
    end
  end
end
