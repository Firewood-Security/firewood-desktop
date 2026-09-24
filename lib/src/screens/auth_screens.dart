// Setup and unlock screens — both use the shared AuthScaffold so forms line up.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

import '../providers.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final password = _password.text;
    final confirm = _confirm.text;
    if (password.length < 8) {
      setState(() => _error = AppStrings.passwordTooShort);
      return;
    }
    if (password != confirm) {
      setState(() => _error = AppStrings.passwordsDoNotMatch);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final vaults = ref.read(vaultServiceProvider);
      await vaults.createVault(password);
      ref.read(authProvider.notifier).state = await vaults.unlock(password);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      logo: Image.asset('assets/FWS.png', width: 76, height: 76),
      title: AppStrings.createVault,
      subtitle: AppStrings.setupSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: AppStrings.masterPassword),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _confirm,
            obscureText: true,
            onSubmitted: (_) => _create(),
            decoration: const InputDecoration(labelText: AppStrings.confirmPassword),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: const TextStyle(color: AppColors.roseAccent, fontSize: 12)),
          ],
          const SizedBox(height: AppSpacing.xl),
          FirewoodButton(
            label: AppStrings.createVault,
            onPressed: _create,
            isLoading: _busy,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await ref.read(vaultServiceProvider).unlock(_password.text);
      ref.read(authProvider.notifier).state = key;
    } on VaultException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      logo: Image.asset('assets/FWS.png', width: 76, height: 76),
      title: AppStrings.unlockVault,
      subtitle: AppStrings.unlockSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _unlock(),
            decoration: const InputDecoration(labelText: AppStrings.masterPassword),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: const TextStyle(color: AppColors.roseAccent, fontSize: 12)),
          ],
          const SizedBox(height: AppSpacing.xl),
          FirewoodButton(
            label: AppStrings.unlock,
            onPressed: _unlock,
            isLoading: _busy,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}
