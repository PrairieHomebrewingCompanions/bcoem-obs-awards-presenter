# Draws the plugin's images into imgs/: the plugin and category icons, the
# action list icons, each action's dial icon, and the touch strip background.
# Each comes at 1x and @2x. They're drawn from shapes alone, so no font or
# artwork is needed. Run from the repository root after changing the look:
#
# usage: elixir streamdeck/tools/draw-images.exs [imgs_dir]
#   (imgs_dir defaults to the plugin's imgs/ folder)

Mix.install([{:image, "~> 0.72"}])

out =
  case System.argv() do
    [dir] ->
      dir

    [] ->
      Path.wildcard("streamdeck/*.sdPlugin/imgs") |> List.first() ||
        raise "run from the repository root"
  end

defmodule Draw do
  @dark "#1d2230"
  @darker "#11141c"
  @gold "#f2b632"

  def gold, do: @gold

  def image(name, w, h, out, draw) do
    for {scale, suffix} <- [{1, ""}, {2, "@2x"}] do
      body = draw.(w * scale, h * scale)

      ~s|<svg xmlns="http://www.w3.org/2000/svg" width="#{w * scale}" height="#{h * scale}">#{body}</svg>|
      |> Image.from_binary!()
      |> Image.write!(Path.join(out, "#{name}#{suffix}.png"))
    end
  end

  # A dark background, lighter at the top.
  def background(w, h) do
    ~s|<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">| <>
      ~s|<stop offset="0" stop-color="#{@dark}"/><stop offset="1" stop-color="#{@darker}"/></linearGradient></defs>| <>
      ~s|<rect width="#{w}" height="#{h}" fill="url(#bg)"/>|
  end

  # A podium: 2nd, 1st and 3rd place blocks.
  def podium(w, h, colour) do
    {bw, base} = {w * 0.24, h * 0.8}

    for {x, height} <- [{0.14, 0.32}, {0.38, 0.5}, {0.62, 0.22}], into: "" do
      ~s|<rect x="#{w * x}" y="#{base - h * height}" width="#{bw}" height="#{h * height}" rx="#{w * 0.02}" fill="#{colour}"/>|
    end
  end

  # The list icons are white-on-transparent glyphs, as the Stream Deck app
  # expects; the dials use the same shapes in gold.
  def dot(w, h, colour), do: ~s|<circle cx="#{w / 2}" cy="#{h / 2}" r="#{w * 0.28}" fill="#{colour}"/>|

  def play(w, h, colour) do
    ~s|<polygon points="#{w * 0.32},#{h * 0.22} #{w * 0.78},#{h * 0.5} #{w * 0.32},#{h * 0.78}" fill="#{colour}"/>|
  end
end

Draw.image("plugin", 256, 256, out, fn w, h -> Draw.background(w, h) <> Draw.podium(w, h, Draw.gold()) end)
Draw.image("category", 28, 28, out, fn w, h -> Draw.podium(w, h, "#fff") end)
Draw.image("live", 20, 20, out, fn w, h -> Draw.dot(w, h, "#fff") end)
Draw.image("next", 20, 20, out, fn w, h -> Draw.play(w, h, "#fff") end)
Draw.image("live-dial", 72, 72, out, fn w, h -> Draw.background(w, h) <> Draw.dot(w, h, Draw.gold()) end)
Draw.image("next-dial", 72, 72, out, fn w, h -> Draw.background(w, h) <> Draw.play(w, h, Draw.gold()) end)
Draw.image("strip", 200, 100, out, fn w, h -> Draw.background(w, h) end)
