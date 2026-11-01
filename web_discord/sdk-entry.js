// esbuild entry: exposes the Embedded App SDK as window.DiscordSDKBundle.
import { DiscordSDK, patchUrlMappings } from '@discord/embedded-app-sdk';
window.DiscordSDKBundle = { DiscordSDK, patchUrlMappings };
