;; Lo que sigue es un "manifest" equivalente a la línea de comando que
;; introdujo. Puede almacenarlo dentro de un archivo que pudiese pasar a
;; cualquier comando 'guix' que acepte una opción '--manifest' (o -m).

(use-modules (guix profiles)
             (gnu packages base)
             (gnu packages bash)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (gnu packages linux)
             (guix git-download)
             (guix packages)
             (guix gexp)
             (guix utils)
             (guix base16)
             (ice-9 match)
             ((guix licenses) #:prefix license:)
             (guix build-system guile))

(define-public maak
  (package
    (name "maak")
    (version "0.12.4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://sl.urutau-ltd.org/guix-contrib/maak.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1hglh7sakqxy71zlyxh8dpydwj7qdj69hzd9yzwyznyml2f0yqlf"))))
    (build-system guile-build-system)
    (arguments
     (list
      #:source-directory "src"
      #:modules '((guix build guile-build-system)
                  (guix build utils)
                  (ice-9 match))
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'build 'install-program-files
            (lambda _
              (let ((bin (string-append #$output "/bin"))
                    (share (string-append #$output "/share")))
                (install-file "resources/help.txt"
                              (string-append share "/resources"))
                (install-file "scripts/maak" bin)
                (chmod (string-append bin "/maak") #o755))))
          (add-after 'unpack 'fix-paths
            (lambda* (#:key inputs #:allow-other-keys)
              (for-each (match-lambda
                          ((pattern program format-string)
                           (substitute* "scripts/maak"
                             ((pattern)
                              (format #f format-string
                                      (search-input-file inputs
                                                         (string-append "bin/"
                                                          program)))))))
                        '(("readlink -f " "readlink" "~s -f ")
                          ("realpath " "realpath" "~s ")
                          ("dirname " "dirname" "~s ")
                          ("getopt " "getopt" "~s ")
                          ("exec guile " "guile" "exec ~s ")))))
          (add-after 'build 'install-completions
            (lambda _
              (for-each (match-lambda
                          ((src-file dest-dir dest-name)
                           (let ((target-dir (string-append #$output dest-dir)))
                             (mkdir-p target-dir)
                             (copy-file src-file
                                        (string-append target-dir "/"
                                                       dest-name)))))
                        '(("scripts/maak-completion.bash"
                           "/share/bash-completion/completions" "maak"))))))))
    (native-inputs (list guile-3.0))
    (inputs (list guile-3.0 bash-minimal coreutils util-linux))
    (home-page "https://codeberg.org/jjba23/maak")
    (synopsis "Command runner à la Make using Guile Scheme")
    (description
     "Maak is a command runner and control plane for your
projects.  It allows you to use the power of Lisp (Guile Scheme) to define
your tasks, build steps, repetitive tasks or other automation.

With Maak you can easily call external shell commands and integrate with
your existing scripts and tools.  It is inspired by the GNU Make utility
but it does away with a lot of the complexity that comes with its history.")
    (license license:gpl3+)))

(concatenate-manifests
 (list (specifications->manifest (list "guile" "zig" "zig-zls"))
       (packages->manifest (list maak))))
