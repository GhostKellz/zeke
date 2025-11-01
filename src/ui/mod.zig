pub const themes = @import("themes.zig");
pub const colors = @import("colors.zig");

pub const Theme = themes.Theme;
pub const TokyoNightVariant = themes.TokyoNightVariant;
pub const getCurrentTheme = themes.getCurrentTheme;

pub const Colors = colors.Colors;
pub const initTheme = colors.initTheme;
pub const printSuccess = colors.printSuccess;
pub const printError = colors.printError;
pub const printWarning = colors.printWarning;
pub const printInfo = colors.printInfo;
pub const printHighlight = colors.printHighlight;
pub const printMuted = colors.printMuted;
pub const printCode = colors.printCode;
pub const printLink = colors.printLink;
