import 'package:flutter/material.dart';

import '../channel.dart';
import '../message_pins/pinned_messages_list.dart';

class ChannelPinsView extends StatelessWidget {
  const ChannelPinsView({super.key, required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) => PinnedMessagesList(channel: channel);
}
