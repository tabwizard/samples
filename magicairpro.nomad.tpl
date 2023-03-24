{{ with secret "secrets/map/redis" }}
Storage__Redis__Host="{{ .Data.host }}"
Storage__Redis__Password="{{ .Data.password }}"
{{ end }}

{{ $kontur := env "NOMAD_NAMESPACE" }}
{{ with secret (print "secrets/map/kontur/" $kontur "/common")  }}
{{ range $k, $v := .Data }}
{{ $k }}="{{ $v }}"
{{ end }}
{{ end }}

{{ with secret (print "secrets/map/kontur/" $kontur "/magicairpro")  }}
{{ range $k, $v := .Data }}
{{ $k }}="{{ $v }}"
{{ end }}
{{ end }}


