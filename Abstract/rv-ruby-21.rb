require File.expand_path("../Abstract/portable-formula", __dir__)

class RvRuby21 < Formula
  def self.inherited(subclass)
    subclass.class_eval do
      super

      desc "Powerful, clean, object-oriented scripting language"
      homepage "https://www.ruby-lang.org/"
      license "Ruby"

      livecheck do
        formula "ruby"
        regex(/href=.*?ruby[._-]v?(2.1.(?:(?!0)\d+)(?:\.\d+)*)\.t/i)
      end

      keg_only "portable formulae are keg-only"

      depends_on "pkgconf" => :build
      depends_on "portable-libyaml@0.2.5" => :build
      depends_on "portable-openssl@3.5.1" => :build

      # skip_clean "lib/ruby/gems"

      on_linux do
        depends_on "portable-libedit" => :build
        depends_on "portable-libffi@3.5.1" => :build
        depends_on "portable-zlib@1.3.1" => :build
      end

      prepend PortableFormulaMixin
    end
  end

  def install
    dep_names = deps.map(&:name)
    libyaml = Formula[dep_names.find{|d| d.start_with?("portable-libyaml") }]

    args = %W[
      --prefix=#{prefix}
      --enable-load-relative
      --with-out-ext=openssl,tk,win32,win32ole,digest/md5,digest/rmd160,digest/sha1,digest/sha2
      --without-gmp
      --disable-install-doc
      --disable-install-rdoc
      --disable-dependency-tracking
    ]

    args += %W[
      --with-libyaml-dir=#{libyaml.opt_prefix}
    ]

    if OS.mac?
      args << "--enable-libedit"
      if Hardware::CPU.arm?
        args << "--build=aarch64-apple-darwin#{OS.kernel_version.to_s.split(".").first}"
        args << "--host=aarch64-apple-darwin#{OS.kernel_version.to_s.split(".").first}"
      end
    end

    if OS.linux?
      libffi = Formula[dep_names.find{|d| d.start_with?("portable-libffi") }]
      zlib = Formula[dep_names.find{|d| d.start_with?("portable-zlib") }]
      libedit = Formula[dep_names.find{|d| d.start_with?("portable-libedit") }]

      args += %W[
        --enable-libedit=#{libedit.opt_prefix}
        --with-libffi-dir=#{libffi.opt_prefix}
        --with-zlib-dir=#{zlib.opt_prefix}
      ]

      args << "MKDIR_P=/bin/mkdir -p"
      args << "ac_cv_lib_z_uncompress=no"
    end

    ENV["cflags"] = ENV.delete("CFLAGS")
    ENV["cppflags"] = ENV.delete("CPPFLAGS")
    ENV["cxxflags"] = ENV.delete("CXXFLAGS")

    if OS.mac? && Hardware::CPU.arm?
      # Hardening the 'rm' command in the generated 'config.status'
      inreplace "configure", 'rm -f "$ac_file"', 'rm -f -- "$ac_file"'
    end

    system "./configure", *args
    system "make"
    system "make", "install"

    abi_version = `#{bin}/ruby -rrbconfig -e 'print RbConfig::CONFIG["ruby_version"]'`
    abi_arch = `#{bin}/ruby -rrbconfig -e 'print RbConfig::CONFIG["arch"]'`

    mkdir_p "lib/#{abi_arch}"
    File.open("lib/#{abi_arch}/portable_ruby_gems.rb", "w") do |file|
      (Dir["extensions/*/*/*", base: ".bundle"] + Dir["gems/*/lib", base: ".bundle"]).each do |require_path|
        file.write <<~RUBY
          $:.unshift "\#{RbConfig::CONFIG["rubylibprefix"]}/gems/\#{RbConfig::CONFIG["ruby_version"]}/#{require_path}"
        RUBY
      end
    end

    if OS.linux?
      rbconfig = lib/"ruby/#{abi_version}/#{abi_arch}/rbconfig.rb"
      if rbconfig.exist?
        content = File.read(rbconfig)
        content.gsub!(ENV.cxx, "c++") if ENV.cxx
        content.gsub!(ENV.cc, "cc") if ENV.cc
        content.gsub!(/(CONFIG\[".+"\] = )"gcc-(.*)-\d+"/, '\\1"\\2"')
        File.write(rbconfig, content)
      end
    end
  end

  def test
    cp_r Dir["#{prefix}/*"], testpath
    ENV["PATH"] = "/usr/bin:/bin"
    ruby = (testpath/"bin/ruby").realpath
    assert_equal version.to_s.split("-").first, shell_output("#{ruby} -e 'puts RUBY_VERSION'").chomp
    assert_equal ruby.to_s, shell_output("#{ruby} -e 'puts RbConfig.ruby'").chomp
    assert_equal '{"a"=>"b"}', shell_output("#{ruby} -ryaml -e 'puts YAML.load(\"a: b\")'").chomp
  end
end
