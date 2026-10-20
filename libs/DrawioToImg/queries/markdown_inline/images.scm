; extends

(inline_link
  (link_destination) @image.src
  (#match? @image.src "\\v(\\.drawio(\\.svg)?|(^|/)diagrams/.*\\.svg)>?$")
  (#gsub! @image.src "^<" "")
  (#gsub! @image.src ">$" "")
) @image
