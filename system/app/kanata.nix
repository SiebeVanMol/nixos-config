{
  hardware.uinput.enable = true;

  services.kanata = {
    enable = true;
    keyboards = {
      default = {
        config = ''
          (defsrc
            grv  1 2 3 4 5 6 7 8 9 0 - = bspc
            tab  q w e r t y u i o p [ ] \
            caps a s d f g h j k l ; ' ret
            lsft z x c v b n m , . / rsft
            lctl lmet lalt spc ralt rmet rctl
          )
          (deflayer qwerty
            @grl 1 2 3 4 5 6 7 8 9 0 - = bspc
            tab  q w e r t y u i o p [ ] \
            caps a s d f g h j k l ; ' ret
            lsft z x c v b n m , . / rsft
            lctl lmet lalt spc ralt rmet rctl
          )
          (deflayer canary-angle
            @grl 1 2 3 4 5 6 7 8 9 0 - = bspc
            tab  w l y p b z f o u ' [ ] \
            caps c r s t g m n e i a ; ret
            lsft q j v d k x h / , . rsft
            _ _ _ _ _ _ _
          )
                    (deflayer command
            _ _ _ _ _ _ _ _ _ _ _ _ _ _
            _ _ _ _ _ _ _ _ up _ _ _ _ _
            _ _ _ _ _ _ _ left down right _ _ _
            _ _ _ _ _ _ _ _ _ _ _ _
            _ _ _ _ _ _ _
          )
          (defalias
            grl (tap-hold 200 200 grv (layer-toggle layers))
           
            qwr (layer-switch qwerty)
            cnr (layer-switch canary-angle)
          )
          (deflayer layers
            _ @qwr @cnr _ _ _ _ _ _ _ _ _ _ _
            _ _ _ _ _ _ _ _ _ _ _ _ _ _
            _ _ _ _ _ _ _ _ _ _ _ _ _
            _ _ _ _ _ _ _ _ _ _ _ _
            _ _ _ _ _ _ _
          )
        '';
        extraDefCfg = "process-unmapped-keys yes";
      };
    };
  };
}
