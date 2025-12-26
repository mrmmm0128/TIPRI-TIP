import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/endUser/utils/design.dart';

/// ダイアログの結果を表すenum
enum TipMessageAction { cancel, skip, ok }

/// ダイアログの結果データ
class TipMessageResult {
  final TipMessageAction action;
  final String? name;
  final String? message;
  final String? email;

  const TipMessageResult({
    required this.action,
    this.name,
    this.message,
    this.email,
  });
}

/// チップ送信時のメッセージ入力ダイアログ
class TipMessageDialog extends StatefulWidget {
  final String? initialName;
  final String? initialMessage;
  final String? initialEmail;
  final int maxNameLength;
  final int maxMessageLength;
  final bool showEmailField;
  final bool showNameField;
  final bool showMessageField;

  const TipMessageDialog({
    super.key,
    this.initialName,
    this.initialMessage,
    this.initialEmail,
    this.maxNameLength = 50,
    this.maxMessageLength = 200,
    this.showEmailField = false,
    this.showNameField = true,
    this.showMessageField = true,
  });

  /// ダイアログを表示して結果を返す
  static Future<TipMessageResult?> show(
    BuildContext context, {
    String? initialName,
    String? initialMessage,
    String? initialEmail,
    int maxNameLength = 50,
    int maxMessageLength = 200,
    bool showEmailField = false,
    bool showNameField = true,
    bool showMessageField = true,
  }) {
    return showDialog<TipMessageResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TipMessageDialog(
        initialName: initialName,
        initialMessage: initialMessage,
        initialEmail: initialEmail,
        maxNameLength: maxNameLength,
        maxMessageLength: maxMessageLength,
        showEmailField: showEmailField,
        showNameField: showNameField,
        showMessageField: showMessageField,
      ),
    );
  }

  @override
  State<TipMessageDialog> createState() => _TipMessageDialogState();
}

class _TipMessageDialogState extends State<TipMessageDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _messageCtrl;
  late final TextEditingController _emailCtrl;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _messageCtrl = TextEditingController(text: widget.initialMessage ?? '');
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _messageCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _isNameEmpty =>
      widget.showNameField && _nameCtrl.text.trim().isEmpty;

  bool get _isEmailInvalid {
    if (!widget.showEmailField) return false;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return true;
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return !regex.hasMatch(email);
  }

  bool get _canSubmit {
    if (widget.showNameField && _isNameEmpty) return false;
    if (widget.showEmailField && _isEmailInvalid) return false;
    return true;
  }

  void _validateEmail() {
    if (!widget.showEmailField) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _emailError = tr('dialog.email_required');
    } else {
      final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (!regex.hasMatch(email)) {
        _emailError = tr('dialog.email_invalid');
      } else {
        _emailError = null;
      }
    }
  }

  void _pop(TipMessageAction action) {
    final name = _nameCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    Navigator.pop(
      context,
      TipMessageResult(
        action: action,
        name: name.isEmpty ? null : name,
        message: action == TipMessageAction.skip
            ? null
            : (message.isEmpty ? null : message),
        email: email.isEmpty ? null : email,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        dialogBackgroundColor: AppPalette.white,
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: AppPalette.black,
          surface: AppPalette.white,
          onSurface: AppPalette.black,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.black,
            textStyle: AppTypography.body(),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppPalette.black,
            backgroundColor: AppPalette.white,
            side: BorderSide(color: AppPalette.black, width: AppDims.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            textStyle: AppTypography.label(),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppPalette.black,
            foregroundColor: AppPalette.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: AppTypography.label(),
          ),
        ),
      ),
      child: SizedBox(
        width: 380,
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: AppPalette.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppPalette.black, width: AppDims.border),
          ),
          title: Text(
            tr('dialog.send_message_title'),
            style: AppTypography.label(color: AppPalette.black),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 360, maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // メール入力欄（必須・サブスク用）
                  if (widget.showEmailField) ...[
                    Text(
                      tr('dialog.email_label'),
                      style: AppTypography.small(color: AppPalette.black),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        _validateEmail();
                        setState(() {});
                      },
                      style: AppTypography.body(color: AppPalette.black),
                      decoration: InputDecoration(
                        hintText: tr('dialog.email_hint'),
                        errorText: _emailError,
                        hintStyle: AppTypography.small(
                          color: AppPalette.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppPalette.white,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // 名前入力欄（必須）
                  if (widget.showNameField) ...[
                    Text(
                      tr('dialog.name_label'),
                      style: AppTypography.small(color: AppPalette.black),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      maxLength: widget.maxNameLength,
                      onChanged: (_) => setState(() {}),
                      style: AppTypography.body(color: AppPalette.black),
                      decoration: InputDecoration(
                        hintText: tr('dialog.name_hint'),
                        hintStyle: AppTypography.small(
                          color: AppPalette.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppPalette.white,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // メッセージ入力欄（任意）
                  if (widget.showMessageField) ...[
                    Text(
                      tr('edit_message_title'),
                      style: AppTypography.small(color: AppPalette.black),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _messageCtrl,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 4,
                      maxLines: 4,
                      maxLength: widget.maxMessageLength,
                      expands: false,
                      style: AppTypography.body(color: AppPalette.black),
                      decoration: InputDecoration(
                        hintText: tr('dialog.message_hint'),
                        hintStyle: AppTypography.small(
                          color: AppPalette.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppPalette.white,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _pop(TipMessageAction.cancel),
                  child: Text(
                    tr('button.back'),
                    style: const TextStyle(
                      fontFamily: "LINEseed",
                      fontSize: 12,
                    ),
                  ),
                ),
                if (widget.showMessageField)
                  OutlinedButton(
                    onPressed: () => _pop(TipMessageAction.skip),
                    child: Text(
                      tr('button.skip'),
                      style: const TextStyle(
                        fontFamily: "LINEseed",
                        fontSize: 12,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _canSubmit
                      ? () => _pop(TipMessageAction.ok)
                      : null,
                  child: Text(
                    tr('button.send'),
                    style: const TextStyle(
                      fontFamily: "LINEseed",
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
