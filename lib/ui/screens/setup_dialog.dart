import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/host_controller.dart';
import '../../core/models.dart';
import '../../services/device_service.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> showSetup(BuildContext context, HostController host) async {
  final name = TextEditingController(text: host.profile.name);
  final contact = TextEditingController(text: host.profile.contact);
  var engine = host.profile.engine;
  var version = host.profile.version;
  final minMb = DeviceService.minMemoryMb;
  final maxMb = host.maxMemoryMb;
  var memory = DeviceService.clampHeapMb(
    host.profile.memoryMb,
    host.deviceRamMb,
  ).toDouble();
  var eula = host.profile.eulaAccepted;
  final form = GlobalKey<FormState>();
  final result = await showDialog<ServerProfile>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        final c = context.hc;
        final recommended = host.recommendedMemoryMb;
        final tooMuch = memory.round() > recommended;
        return AlertDialog(
          title: const Text('Create your corner of Minecraft'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Server name',
                      ),
                      maxLength: 40,
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Give your server a name' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ServerEngine>(
                      isExpanded: true,
                      initialValue: engine,
                      decoration: const InputDecoration(
                        labelText: 'Server software',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ServerEngine.vanilla,
                          child: Text('Vanilla · official Mojang server'),
                        ),
                        DropdownMenuItem(
                          value: ServerEngine.paper,
                          child: Text('Paper · plugins & performance'),
                        ),
                      ],
                      onChanged: (v) => set(() => engine = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: version,
                      decoration: const InputDecoration(
                        labelText: 'Minecraft version',
                      ),
                      items: const ['1.21.1', '1.20.4']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => set(() => version = v!),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Each software/version pair uses a separate world folder. These initial versions run on Java 21.',
                      style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
                    ),
                    if (engine == ServerEngine.paper) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: contact,
                        decoration: const InputDecoration(
                          labelText: 'Contact email or project URL',
                          helperText: 'Required by the Paper download API',
                        ),
                        validator: (v) =>
                            v == null ||
                                !(v.contains('@') || v.startsWith('https://'))
                            ? 'Enter your contact email or HTTPS project URL'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Memory allocation  ·  ${gigabytes(memory)} GB',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Slider(
                      value: memory,
                      min: minMb.toDouble(),
                      max: maxMb.toDouble(),
                      divisions: math.max(
                        1,
                        (maxMb - minMb) ~/ DeviceService.memoryStepMb,
                      ),
                      onChanged: (v) => set(() => memory = v),
                    ),
                    Text(
                      host.ramDetected
                          ? 'This device has ${gigabytes(host.deviceRamMb)} GB of RAM. Up to ${gigabytes(recommended)} GB is recommended.'
                          : 'HostCraft could not read this device\'s RAM, so the limit shown is an estimate.',
                      style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
                    ),
                    if (tooMuch) ...[
                      const SizedBox(height: 10),
                      Notice(
                        text: Platform.isAndroid
                            ? 'That leaves little memory for Android. The system may stop the server or HostCraft.'
                            : 'That leaves little memory for your system and other apps.',
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: eula,
                      onChanged: (v) => set(() => eula = v!),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'I have read and agree to the Minecraft EULA.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          openLink(context, 'https://www.minecraft.net/eula'),
                      child: const Text('Read the Minecraft EULA ↗'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: eula
                  ? () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(
                          context,
                          ServerProfile(
                            name: name.text.trim(),
                            engine: engine,
                            version: version,
                            memoryMb: memory.round(),
                            eulaAccepted: eula,
                            contact: contact.text.trim(),
                          ),
                        );
                      }
                    }
                  : null,
              child: const Text('Save setup'),
            ),
          ],
        );
      },
    ),
  );
  // Controllers belong to the dialog route until its closing animation finishes.
  if (result != null) await host.action(() => host.configure(result));
}
