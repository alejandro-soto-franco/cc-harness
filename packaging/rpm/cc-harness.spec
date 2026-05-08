%global goipath github.com/alejandro-soto-franco/cc-harness

Name:           cc-harness
Version:        0.1.0
Release:        1%{?dist}
Summary:        Multi-session Claude Code launcher backed by tmux

License:        MIT
URL:            https://github.com/alejandro-soto-franco/%{name}
Source0:        %{url}/releases/download/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  make
BuildRequires:  pandoc
Requires:       bash
Requires:       tmux >= 3.0
Recommends:     fzf

%description
cc-harness runs multiple Claude Code sessions in parallel inside one tmux
session, with one named window per project. A persistent menu window acts
as the control loop for spawning, switching, and killing sessions; tmux
keeps everything alive across SSH disconnects.

%prep
%autosetup -n %{name}-%{version}

%build
make completions
make man

%install
make install \
    DESTDIR=%{buildroot} \
    PREFIX=%{_prefix} \
    BINDIR=%{_bindir} \
    MANDIR=%{_mandir} \
    BASH_COMPLETION_DIR=%{_datadir}/bash-completion/completions \
    ZSH_COMPLETION_DIR=%{_datadir}/zsh/site-functions \
    FISH_COMPLETION_DIR=%{_datadir}/fish/vendor_completions.d

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/%{name}
%{_mandir}/man1/%{name}.1*
%{_datadir}/bash-completion/completions/%{name}
%{_datadir}/zsh/site-functions/_%{name}
%{_datadir}/fish/vendor_completions.d/%{name}.fish
%{_datadir}/%{name}/projects.conf.example

%changelog
* Fri May 08 2026 Alejandro Soto Franco <sotofranco.eng@gmail.com> - 0.1.0-1
- Initial package release for v0.1.0.
