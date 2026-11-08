local ADDON, A = ...

-- /almanac and the key binding.
local Slash = {}
A.Slash = Slash

SLASH_ALMANAC1 = "/almanac"
SLASH_ALMANAC2 = "/alm"
SlashCmdList["ALMANAC"] = function(msg) Slash.Handle(msg) end

BINDING_HEADER_AUCTIONATORALMANAC = "Auctionator Almanac"
BINDING_NAME_ALMANAC_TOGGLE = "Toggle the Almanac window"

-- Referenced from Bindings.xml
function AuctionatorAlmanac_Toggle()
  A.UI.Window.Toggle()
end

local HELP = {
  "/almanac - open or close the window",
  "/almanac search <text> - open it with a search",
  "/almanac options - open the options",
  "/almanac refresh - re-read Auctionator's saved prices",
  "/almanac debug - show which game features were found",
  "/almanac reset <ledger|inventory|history|items> confirm - erase stored data",
  "/almanac reset window - put the window back in the middle",
}

local RESET_TEXT = {
  ledger = "all recorded sales, purchases and postings",
  inventory = "what every character owns",
  history = "the long-term price history, watch list and viewed items",
  items = "the item name cache (it reloads by itself)",
}

function Slash.Handle(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local command, rest = msg:match("^(%S+)%s*(.-)$")
  command = command and command:lower() or ""

  if command == "" then
    A.UI.Window.Toggle()
  elseif command == "show" or command == "open" then
    A.UI.Window.Show()
  elseif command == "hide" or command == "close" then
    A.UI.Window.Hide()
  elseif command == "options" or command == "settings" or command == "config" then
    A.UI.Settings.Toggle()
  elseif command == "debug" then
    A.Debug.Print()
  elseif command == "refresh" or command == "reload" then
    A.Controller.CheckForNewData(true)
  elseif command == "search" then
    A.UI.Window.Show()
    A.Controller.SetSearchText(rest)
    A.UI.SearchBar.Sync()
  elseif command == "reset" then
    local what, confirm = rest:match("^(%S+)%s*(%S*)$")
    what = what and what:lower()
    if what == "window" then
      A.UI.Window.ResetGeometry()
      A.Print("Window position and size reset.")
    elseif what and RESET_TEXT[what] then
      if confirm:lower() == "confirm" then
        A.Main.Reset(what)
        A.Print("Erased " .. RESET_TEXT[what] .. ".")
      else
        A.Print("This erases " .. RESET_TEXT[what] .. ". Type /almanac reset " .. what .. " confirm to go ahead.")
      end
    else
      A.Print("Usage: /almanac reset <ledger|inventory|history|items|window>")
    end
  else
    for _, line in ipairs(HELP) do A.Print(line) end
  end
end
