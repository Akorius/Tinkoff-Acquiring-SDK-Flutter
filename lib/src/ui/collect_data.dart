import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';

import '../core/constants.dart';
import '../core/tinkoff_acquiring.dart';
import '../core/utils/crypto_utils.dart';

/// Сбор данных для прохождения 3-D Secure 2.0 Collect
class CollectData {
  /// Конструктор cбора данных для прохождения 3-D Secure 2.0 Collect
  CollectData({
    @required this.context,
    @required this.onFinished,
    @required this.acquiring,
    @required this.serverTransId,
    @required this.threeDsMethodUrl,
  })  : assert(context != null),
        assert(onFinished != null),
        assert(acquiring != null),
        assert(serverTransId != null),
        assert(threeDsMethodUrl != null) {
    _showDialog(context);
  }

  /// Необходим для встраивания в `widget tree`
  final BuildContext context;

  /// Конфигуратор SDK
  final TinkoffAcquiring acquiring;

  /// Уникальный идентификатор транзакции, генерируемый 3DS-Server,
  /// обязательный параметр для 3DS второй версии
  final String serverTransId;

  /// Дополнительный параметр для 3DS второй версии,
  /// который позволяет пройти этап по сбору данных браузера ACS-ом
  final String threeDsMethodUrl;

  /// Результат проверки
  final void Function(Map<String, String>) onFinished;

  OverlayEntry _overlayEntry;

  void _showDialog(BuildContext context) {
    final OverlayState overlayState = Overlay.of(context, rootOverlay: true);
    _overlayEntry = _createOverlayEntry();
    overlayState.insert(_overlayEntry);
  }

  void _hideDialog() {
    _overlayEntry.remove();
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      maintainState: true,
      builder: (BuildContext context) {
        return Positioned(
          top: 0,
          right: 0,
          width: 1,
          height: 1,
          child: _WebViewCollect(
            acquiring: acquiring,
            serverTransId: serverTransId,
            threeDsMethodUrl: threeDsMethodUrl,
            onFinished: (Map<String, String> map) {
              onFinished(map);
              _hideDialog();
            },
          ),
        );
      },
    );
  }
}

class _WebViewCollect extends StatelessWidget {
  const _WebViewCollect({
    Key key,
    @required this.onFinished,
    @required this.acquiring,
    @required this.serverTransId,
    @required this.threeDsMethodUrl,
  })  : assert(onFinished != null),
        assert(acquiring != null),
        assert(serverTransId != null),
        assert(threeDsMethodUrl != null),
        super(key: key);

  final TinkoffAcquiring acquiring;
  final String serverTransId;
  final String threeDsMethodUrl;
  final void Function(Map<String, String>) onFinished;

  String get termUrl => Uri.encodeFull((acquiring.debug
          ? NetworkSettings.apiUrlDebug
          : NetworkSettings.apiUrlRelease) +
      ApiMethods.submit3DSAuthorizationV2);

  String get notificationsUrl => Uri.encodeFull((acquiring.debug
          ? NetworkSettings.apiUrlDebug
          : NetworkSettings.apiUrlRelease) +
      ApiMethods.complete3DSMethodv2);

  String get createCollectData {
    final Map<String, String> params = <String, String>{
      WebViewKeys.threeDSServerTransId: serverTransId,
      WebViewKeys.threeDSMethodNotificationURL: notificationsUrl,
    };

    return CryptoUtils.base64(Uint8List.fromList(jsonEncode(params).codeUnits))
        .trim();
  }

  String get collect => '''
      <html>
        <body onload="document.f.submit();">
          <form name="payForm" action="$threeDsMethodUrl" method="POST">
            <input type="hidden" name="threeDSMethodData" value="$createCollectData"/>
          </form>
          <script>
            window.onload = submitForm;
            function submitForm() { payForm.submit(); }
          </script>
        </body>
      </html>
    ''';

  @override
  Widget build(BuildContext context) {
    return WebView(
      initialUrl: '',
      gestureNavigationEnabled: true,
      javascriptMode: JavascriptMode.unrestricted,
      onWebViewCreated: (WebViewController webViewController) {
        webViewController.loadUrl(Uri.dataFromString(
          collect,
          mimeType: 'text/html',
          encoding: Encoding.getByName('utf-8'),
        ).toString());
      },
      onPageFinished: (String url) async {
        if (url == notificationsUrl) {
          final Window win = WidgetsBinding.instance.window;
          onFinished(<String, String>{
            WebViewKeys.threeDSCompInd: 'Y',
            WebViewKeys.language:
                Localizations.localeOf(context).toLanguageTag(),
            WebViewKeys.timezone: '${DateTime.now().timeZoneOffset.inMinutes}',
            WebViewKeys.screenHeight:
                win.physicalSize.height.toStringAsFixed(0),
            WebViewKeys.screenWidth: win.physicalSize.width.toStringAsFixed(0),
            WebViewKeys.cresCallbackUrl: termUrl,
          });
        }
      },
    );
  }
}
