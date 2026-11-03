import 'package:flutter/material.dart';

class EntryField {
  const EntryField(
    this.key,
    this.label, {
    this.money = false,
    this.options,
    this.initial,
  });
  final String key, label;
  final bool money;
  final Map<String, String>? options;
  final String? initial;
}

Future<Map<String, String>?> entryForm(
  BuildContext context,
  String title,
  List<EntryField> fields,
) =>
    showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _EntryDialog(title, fields),
    );

class _EntryDialog extends StatefulWidget {
  const _EntryDialog(this.title, this.fields);
  final String title;
  final List<EntryField> fields;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final form = GlobalKey<FormState>();
  final values = <String, String>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      values[field.key] = field.initial ?? field.options?.keys.first ?? '';
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in widget.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: field.options == null
                          ? TextFormField(
                              initialValue: values[field.key],
                              decoration:
                                  InputDecoration(labelText: field.label),
                              keyboardType: field.money
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                    )
                                  : TextInputType.text,
                              maxLength: field.money ? 13 : 100,
                              onChanged: (value) => values[field.key] = value,
                              validator: (value) => value!.trim().isEmpty
                                  ? 'Required'
                                  : field.money &&
                                          !RegExp(r'^\d{1,10}(\.\d{1,2})?$')
                                              .hasMatch(value.trim())
                                      ? 'Enter a valid amount'
                                      : null,
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: values[field.key],
                              isExpanded: true,
                              decoration:
                                  InputDecoration(labelText: field.label),
                              items: [
                                for (final choice in field.options!.entries)
                                  DropdownMenuItem(
                                    value: choice.key,
                                    child: Text(
                                      choice.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) => values[field.key] = value!,
                            ),
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
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, values);
            },
            child: const Text('Save'),
          ),
        ],
      );
}

Future<void> perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst(
                  RegExp(
                      r'^(Bad state|FormatException|Invalid argument\(s\)): '),
                  '',
                ),
          ),
        ),
      );
    }
  }
}
