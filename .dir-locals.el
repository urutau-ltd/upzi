;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")

((nil . ((compile-command . "maak build")
         (eval . (editorconfig-mode 1))
         (eval . (when (and buffer-file-name
                            (string-match-p "\\.scm\\'" buffer-file-name))
                   (paredit-mode 1))))))
