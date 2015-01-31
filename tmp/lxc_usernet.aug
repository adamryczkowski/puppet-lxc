module LXC_usernet =

let entry = [ seq "entry"
            . [ label "name" . store Rx.word ] . Sep.space
            . [ label "type" . store Rx.word ] . Sep.space
            . [ label "dev" . store Rx.word ] . Sep.space
            . [ label "value" . store Rx.word ] . Util.eol ]

let lns = (Util.empty | Util.comment | entry)*


