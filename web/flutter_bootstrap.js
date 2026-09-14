{{flutter_js}}
{{flutter_build_config}}

const isAndroid = /Android/i.test(navigator.userAgent);

_flutter.loader.load({
  config: isAndroid
      ? {
          canvasKitForceCpuOnly: true,
        }
      : {},
});
