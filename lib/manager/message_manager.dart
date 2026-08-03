import 'dart:async';
import 'dart:math';

import 'package:avee/common/common.dart';
import 'package:avee/models/models.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:avee/widgets/fade_box.dart';
import 'package:flutter/material.dart';

class MessageManager extends StatefulWidget {
  const MessageManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  State<MessageManager> createState() => MessageManagerState();
}

class MessageManagerState extends State<MessageManager> {
  final _messagesNotifier = ValueNotifier<List<CommonMessage>>([]);
  final List<CommonMessage> _bufferMessages = [];
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _messagesNotifier.dispose();
    super.dispose();
  }

  Future<void> message(String text) async {
    final commonMessage = CommonMessage(
      id: utils.uuidV4,
      text: text,
    );
    commonPrint.log(text);
    _bufferMessages.add(commonMessage);
    await _showMessage();
  }

  Future<void> _showMessage() async {
    if (_pushing == true) {
      return;
    }
    _pushing = true;
    while (_bufferMessages.isNotEmpty) {
      final commonMessage = _bufferMessages.removeAt(0);
      // Bail before mutating if the State was disposed mid-drain: the
      // ValueNotifier is disposed in dispose() and mutating it throws.
      if (!mounted) return;
      _messagesNotifier.value = List.from(_messagesNotifier.value)
        ..add(
          commonMessage,
        );
      await Future.delayed(const Duration(seconds: 1));
      // The manager may have been disposed during the delay above.
      if (!mounted) return;
      Future.delayed(commonMessage.duration, () {
        _handleRemove(commonMessage);
      });
      if (_bufferMessages.isEmpty) {
        _pushing = false;
      }
    }
  }

  Future<void> _handleRemove(CommonMessage commonMessage) async {
    // Fired from a delayed callback; the State (and its ValueNotifier) may have
    // been disposed by the time this runs.
    if (!mounted) return;
    _messagesNotifier.value = List<CommonMessage>.from(_messagesNotifier.value)
      ..remove(commonMessage);
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          widget.child,
          ValueListenableBuilder(
            valueListenable: _messagesNotifier,
            builder: (context, messages, __) {
              final layout = AveeLayout.of(context);
              return FadeThroughBox(
                margin: EdgeInsets.only(
                  top: kToolbarHeight + layout.s(8),
                  left: layout.s(12),
                  right: layout.s(12),
                ),
                alignment: Alignment.topRight,
                child: messages.isEmpty
                    ? const SizedBox()
                    : LayoutBuilder(
                        key: Key(messages.last.id),
                        builder: (_, constraints) => Card(
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(layout.s(Lumina.radiusLg)),
                            ),
                          ),
                          elevation: 10,
                          color: context.colorScheme.surfaceContainerHigh,
                          child: Container(
                            width: min(
                              constraints.maxWidth,
                              layout.dialogMaxWidth,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.s(16),
                              vertical: layout.s(18),
                            ),
                            child: Text(
                              messages.last.text,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontSize: 15),
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
        ],
      );
}
