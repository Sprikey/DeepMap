<script>
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, setSiteLanguage } from '$lib/i18n/site.js';
    import { profileTranslations } from '$lib/i18n/profile.js';

    import {
        AVATAR_PRESETS,
        getDisplayName,
        getGoogleAvatarUrl,
        getAvatarPresentation,
        getCustomAvatarPath,
        getCustomAvatarUrl
    } from '$lib/avatar/avatars.js';

    const MAX_DISPLAY_NAME = 40;
    const MAX_BIO_LENGTH = 200;
    const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;
    const RESERVED_USERNAMES = new Set([
        'admin', 'administrator', 'deepmap', 'official', 'moderator',
        'support', 'staff', 'system', 'root', 'contact', 'help'
    ]);
    const MAX_AVATAR_BYTES = 2 * 1024 * 1024;
    const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

    let currentLanguage = $state('en');
    let t = $derived(profileTranslations[currentLanguage] ?? profileTranslations.en);

    let user = $state(null);
    let checkingSession = $state(true);
    let working = $state(false);
    let errorMessage = $state('');
    let successMessage = $state('');
    let avatarFailed = $state(false);

    // Nome e biografia
    let editingName = $state(false);
    let nameInput = $state('');
    let editingBio = $state(false);
    let bioInput = $state('');

    // @username público: associado ao UUID em public.profiles, não ao nome editável.
    let username = $state(null);
    let usernameLoading = $state(true);
    let usernameLoadError = $state('');
    let editingUsername = $state(false);
    let usernameInput = $state('');
    let usernameError = $state('');
    let usernameCheckStatus = $state('idle');
    let usernameUserId = null;
    let usernameLoadVersion = 0;
    let usernameCheckVersion = 0;
    let usernameCheckTimer = null;

    let usernameStatusMessage = $derived({
        checking: t.username_checking,
        available: t.username_available,
        taken: t.username_taken,
        invalid: t.username_format_error,
        reserved: t.username_reserved,
        check_error: t.username_check_error
    }[usernameCheckStatus] ?? '');

    let displayName = $derived(getDisplayName(user));
    let bio = $derived(
        typeof user?.user_metadata?.bio === 'string'
            ? user.user_metadata.bio
            : ''
    );

    let avatarPresentation = $derived(getAvatarPresentation(user));
    let avatarUrl = $derived(avatarPresentation.image);
    let avatarChoice = $derived(avatarPresentation.choice);
    let googleAvatarUrl = $derived(getGoogleAvatarUrl(user));
    let customAvatarUrl = $derived(getCustomAvatarUrl(user));
    let initial = $derived(displayName.charAt(0).toLocaleUpperCase('pt-PT'));

    // Modal de avatares
    let avatarDialog;
    let avatarFileInput;
    let pendingAvatarChoice = $state(null);
    let pendingAvatarFile = $state(null);
    let pendingAvatarPreview = $state(null);
    let pendingAvatarFilename = $state('');
    let processingFile = $state(false);
    let avatarModalError = $state('');
    let fileSelectionVersion = 0;

    let canSaveAvatar = $derived(
        !!pendingAvatarChoice &&
        (pendingAvatarChoice !== 'custom' || !!pendingAvatarFile || !!customAvatarUrl)
    );

    function changeLanguage(event) {
        currentLanguage = setSiteLanguage(event.currentTarget.value);
    }

    onMount(() => {
        currentLanguage = setSiteLanguage(getSiteLanguage());
        const supabase = getSupabaseBrowserClient();
        let active = true;

        async function checkSession() {
            const { data, error } = await supabase.auth.getUser();
            if (!active) return;

            if (error && error.name !== 'AuthSessionMissingError') {
                errorMessage = t.session_error;
            }

            user = error ? null : data.user;
            if (user && user.id !== usernameUserId) {
                void loadUsername(user.id);
            } else if (!user) {
                resetUsernameState();
            }
            checkingSession = false;
        }

        checkSession();

        const { data: { subscription } } =
            supabase.auth.onAuthStateChange((event, session) => {
                if (!active || event === 'INITIAL_SESSION') return;
                user = session?.user ?? null;
                if (!user) {
                    resetUsernameState();
                } else if (user.id !== usernameUserId) {
                    void loadUsername(user.id);
                }
                avatarFailed = false;
                checkingSession = false;
            });

        return () => {
            active = false;
            usernameLoadVersion++;
            stopUsernameCheck();
            fileSelectionVersion++;
            clearAvatarFile();
            subscription.unsubscribe();
        };
    });


    // ==========================================
    // @USERNAME — TABELA PUBLIC.PROFILES
    // ==========================================

    function stopUsernameCheck() {
        usernameCheckVersion++;
        if (usernameCheckTimer !== null) clearTimeout(usernameCheckTimer);
        usernameCheckTimer = null;
    }

    function resetUsernameState() {
        usernameLoadVersion++;
        stopUsernameCheck();
        usernameUserId = null;
        username = null;
        usernameLoading = false;
        usernameLoadError = '';
        editingUsername = false;
        usernameInput = '';
        usernameError = '';
        usernameCheckStatus = 'idle';
    }

    async function loadUsername(userId) {
        const ticket = ++usernameLoadVersion;
        usernameUserId = userId;
        username = null;
        usernameLoading = true;
        usernameLoadError = '';
        editingUsername = false;
        stopUsernameCheck();

        try {
            const { data, error } = await getSupabaseBrowserClient()
                .from('profiles')
                .select('username')
                .eq('id', userId)
                .maybeSingle();

            if (ticket !== usernameLoadVersion) return;
            if (error) {
                usernameLoadError = t.username_load_error;
                return;
            }
            username = data?.username ?? null;
        } catch {
            if (ticket === usernameLoadVersion) usernameLoadError = t.username_load_error;
        } finally {
            if (ticket === usernameLoadVersion) usernameLoading = false;
        }
    }

    function startEditingUsername() {
        if (working || !user || usernameLoading || usernameLoadError) return;
        stopUsernameCheck();
        usernameInput = username ?? '';
        usernameCheckStatus = 'idle';
        usernameError = '';
        errorMessage = '';
        successMessage = '';
        editingUsername = true;
    }

    function cancelEditingUsername() {
        if (working) return;
        stopUsernameCheck();
        editingUsername = false;
        usernameInput = '';
        usernameCheckStatus = 'idle';
        usernameError = '';
    }

    async function checkUsernameAvailability(candidate, ticket) {
        if (ticket !== usernameCheckVersion || !user || !editingUsername) return;
        try {
            const { data, error } = await getSupabaseBrowserClient()
                .from('profiles')
                .select('id')
                .eq('username', candidate)
                .maybeSingle();

            if (ticket !== usernameCheckVersion || !editingUsername) return;
            if (error) {
                usernameCheckStatus = 'check_error';
                return;
            }
            usernameCheckStatus = data && data.id !== user.id ? 'taken' : 'available';
        } catch {
            if (ticket === usernameCheckVersion && editingUsername) {
                usernameCheckStatus = 'check_error';
            }
        }
    }

    function handleUsernameInput(event) {
        const value = event.currentTarget.value.toLowerCase();
        event.currentTarget.value = value;
        usernameInput = value;
        usernameError = '';
        stopUsernameCheck();

        if (!value || value === username) {
            usernameCheckStatus = 'idle';
        } else if (!USERNAME_PATTERN.test(value)) {
            usernameCheckStatus = 'invalid';
        } else if (RESERVED_USERNAMES.has(value)) {
            usernameCheckStatus = 'reserved';
        } else {
            usernameCheckStatus = 'checking';
            const ticket = usernameCheckVersion;
            usernameCheckTimer = setTimeout(
                () => void checkUsernameAvailability(value, ticket),
                400
            );
        }
    }

    async function saveUsername(event) {
        event.preventDefault();
        if (working || !user || usernameLoading || usernameLoadError) return;
        usernameError = '';
        errorMessage = '';
        successMessage = '';

        const candidate = usernameInput.trim().toLowerCase();
        if (!USERNAME_PATTERN.test(candidate)) {
            usernameCheckStatus = 'invalid';
            return;
        }
        if (RESERVED_USERNAMES.has(candidate)) {
            usernameCheckStatus = 'reserved';
            return;
        }
        if (candidate === username) {
            cancelEditingUsername();
            return;
        }
        if (usernameCheckStatus === 'taken') return;

        stopUsernameCheck();
        working = true;
        const supabase = getSupabaseBrowserClient();

        try {
            // Evita upsert: as permissões SQL só autorizam UPDATE da coluna username.
            const query = username
                ? supabase.from('profiles').update({ username: candidate }).eq('id', user.id)
                : supabase.from('profiles').insert({ id: user.id, username: candidate });
            const { data, error } = await query.select('username').single();

            if (error || !data) {
                if (error?.code === '23505') {
                    usernameCheckStatus = 'taken';
                } else if (error?.code === '23514') {
                    usernameError = t.username_format_error;
                } else {
                    usernameError = t.username_save_error;
                }
                return;
            }

            username = data.username;
            editingUsername = false;
            usernameInput = '';
            usernameCheckStatus = 'idle';
            successMessage = t.username_saved;
        } catch {
            usernameError = t.username_save_error;
        } finally {
            working = false;
        }
    }

    function startEditingName() {
        if (working) return;
        nameInput = displayName;
        editingName = true;
        errorMessage = '';
        successMessage = '';
    }

    function cancelEditingName() {
        if (working) return;
        editingName = false;
        nameInput = '';
        errorMessage = '';
    }

    async function saveDisplayName(event) {
        event.preventDefault();
        if (working || !user) return;
        errorMessage = '';
        successMessage = '';

        const cleanName = nameInput.trim().replace(/\s+/g, ' ');
        if (cleanName.length < 2 || cleanName.length > MAX_DISPLAY_NAME) {
            errorMessage = t.name_length_error;
            return;
        }
        if (cleanName === displayName) {
            cancelEditingName();
            return;
        }

        working = true;
        const { data, error } = await getSupabaseBrowserClient().auth.updateUser({
            data: { display_name: cleanName }
        });
        working = false;

        if (error || !data.user) {
            errorMessage = error?.message || t.name_save_error;
            return;
        }
        user = data.user;
        nameInput = '';
        editingName = false;
        successMessage = t.name_saved;
    }

    function startEditingBio() {
        if (working) return;
        bioInput = bio;
        editingBio = true;
        errorMessage = '';
        successMessage = '';
    }

    function cancelEditingBio() {
        if (working) return;
        editingBio = false;
        bioInput = '';
        errorMessage = '';
    }

    async function saveBio(event) {
        event.preventDefault();
        if (working || !user) return;
        errorMessage = '';
        successMessage = '';

        const cleanBio = bioInput.trim();
        if (cleanBio.length > MAX_BIO_LENGTH) {
            errorMessage = t.bio_length_error;
            return;
        }
        if (cleanBio === bio) {
            cancelEditingBio();
            return;
        }

        working = true;
        const { data, error } = await getSupabaseBrowserClient().auth.updateUser({
            data: { bio: cleanBio }
        });
        working = false;

        if (error || !data.user) {
            errorMessage = error?.message || t.bio_save_error;
            return;
        }
        user = data.user;
        bioInput = '';
        editingBio = false;
        successMessage = t.bio_saved;
    }

    function clearAvatarFile() {
        if (pendingAvatarPreview) URL.revokeObjectURL(pendingAvatarPreview);
        pendingAvatarFile = null;
        pendingAvatarPreview = null;
        pendingAvatarFilename = '';
        if (avatarFileInput) avatarFileInput.value = '';
    }

    function openAvatarModal() {
        if (working || !user || !avatarDialog) return;
        fileSelectionVersion++;
        clearAvatarFile();
        pendingAvatarChoice = avatarChoice === 'initial' ? null : avatarChoice;
        avatarModalError = '';
        errorMessage = '';
        successMessage = '';
        avatarDialog.showModal();
    }

    function closeAvatarModal() {
        if (working) return;
        avatarDialog?.close();
        resetAvatarModal();
    }

    function resetAvatarModal() {
        fileSelectionVersion++;
        clearAvatarFile();
        processingFile = false;
        pendingAvatarChoice = null;
        avatarModalError = '';
    }

    function selectAvatar(choice) {
        if (working || processingFile) return;
        fileSelectionVersion++;
        clearAvatarFile();
        pendingAvatarChoice = choice;
        avatarModalError = '';
    }

    function isRealImage(file, bytes) {
        if (file.type === 'image/jpeg') {
            return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
        }
        if (file.type === 'image/png') {
            return bytes.slice(0, 8).every((b, i) =>
                b === [137, 80, 78, 71, 13, 10, 26, 10][i]
            );
        }
        if (file.type === 'image/webp') {
            return String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF' &&
                String.fromCharCode(...bytes.slice(8, 12)) === 'WEBP';
        }
        return false;
    }

    // getRandomValues funciona também nos testes locais por HTTP/IP,
    // onde crypto.randomUUID pode estar indisponível.
    function createAvatarId() {
        const bytes = crypto.getRandomValues(new Uint8Array(16));
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
        return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
    }

    // Remove EXIF, limita dimensões e guarda um quadrado WebP 512×512.
    async function handleAvatarFile(event) {
        const file = event.currentTarget.files?.[0];
        if (!file || working) return;
        const ticket = ++fileSelectionVersion;
        clearAvatarFile();
        avatarModalError = '';

        if (!IMAGE_TYPES.has(file.type)) {
            avatarModalError = t.image_type_error;
            return;
        }
        if (file.size > MAX_AVATAR_BYTES) {
            avatarModalError = t.image_size_error;
            return;
        }

        processingFile = true;
        let bitmap;
        try {
            const bytes = new Uint8Array(await file.slice(0, 12).arrayBuffer());
            if (!isRealImage(file, bytes)) throw new Error('invalid-image');

            bitmap = await createImageBitmap(file);
            if (bitmap.width * bitmap.height > 24_000_000) {
                throw new Error('oversized-image');
            }

            const canvas = document.createElement('canvas');
            canvas.width = 512;
            canvas.height = 512;
            const context = canvas.getContext('2d');
            if (!context) throw new Error('canvas-failed');

            const side = Math.min(bitmap.width, bitmap.height);
            context.drawImage(
                bitmap,
                (bitmap.width - side) / 2,
                (bitmap.height - side) / 2,
                side, side,
                0, 0, 512, 512
            );

            const blob = await new Promise((resolve) =>
                canvas.toBlob(resolve, 'image/webp', 0.84)
            );
            if (!blob || blob.type !== 'image/webp' || blob.size > MAX_AVATAR_BYTES) {
                throw new Error('canvas-failed');
            }
            if (ticket !== fileSelectionVersion) return;

            pendingAvatarFile = new File([blob], 'avatar.webp', { type: 'image/webp' });
            pendingAvatarPreview = URL.createObjectURL(pendingAvatarFile);
            pendingAvatarFilename = file.name;
            pendingAvatarChoice = 'custom';
        } catch (error) {
            if (ticket !== fileSelectionVersion) return;
            avatarModalError = error?.message === 'invalid-image'
                ? t.image_invalid_error
                : error?.message === 'oversized-image'
                    ? t.image_dimensions_error
                    : t.image_process_error;
        } finally {
            bitmap?.close?.();
            if (ticket === fileSelectionVersion) processingFile = false;
        }
    }

    async function saveAvatar() {
        if (working || processingFile || !user || !canSaveAvatar) return;
        const choice = pendingAvatarChoice;
        const allowed =
            (choice === 'google' && googleAvatarUrl) ||
            (choice === 'custom' && (pendingAvatarFile || customAvatarUrl)) ||
            AVATAR_PRESETS.some((item) => item.id === choice);
        if (!allowed) {
            avatarModalError = t.invalid_avatar;
            return;
        }
        if (avatarChoice === choice && !(choice === 'custom' && pendingAvatarFile)) {
            closeAvatarModal();
            return;
        }

        working = true;
        avatarModalError = '';
        errorMessage = '';
        successMessage = '';

        const supabase = getSupabaseBrowserClient();
        const previousPath = getCustomAvatarPath(user);
        let uploadedPath = null;
        let successful = false;

        try {
            const metadata = { avatar_choice: choice };

            if (choice === 'custom') {
                if (pendingAvatarFile) {
                    uploadedPath = `${user.id}/avatar-${createAvatarId()}.webp`;
                    const { error: uploadError } = await supabase.storage
                        .from('avatars')
                        .upload(uploadedPath, pendingAvatarFile, {
                            contentType: 'image/webp',
                            cacheControl: '3600',
                            upsert: false
                        });
                    if (uploadError) {
                        avatarModalError = uploadError.message || t.avatar_upload_error;
                        return;
                    }
                }

                metadata.avatar_custom_path = uploadedPath || previousPath;
                if (!metadata.avatar_custom_path) {
                    avatarModalError = t.image_no_file_error;
                    return;
                }
            }

            const { data, error } = await supabase.auth.updateUser({ data: metadata });
            if (error || !data.user) {
                avatarModalError = error?.message || t.avatar_save_error;
                if (uploadedPath) {
                    await supabase.storage.from('avatars').remove([uploadedPath]);
                }
                return;
            }

            user = data.user;
            avatarFailed = false;
            successMessage = t.avatar_saved;
            successful = true;

            // Só eliminar a imagem antiga DEPOIS de a nova estar guardada no perfil.
            if (uploadedPath && previousPath && previousPath !== uploadedPath) {
                const { error: removeError } = await supabase.storage
                    .from('avatars')
                    .remove([previousPath]);
                if (removeError) console.warn('Previous DeepMap avatar cleanup:', removeError.message);
            }
        } catch (error) {
            avatarModalError = t.avatar_save_error;
            console.error('DeepMap avatar:', error);
        } finally {
            working = false;
        }

        if (successful) {
            avatarDialog?.close();
            resetAvatarModal();
        }
    }

    async function logout() {
        if (working) return;
        working = true;
        errorMessage = '';

        const { error } = await getSupabaseBrowserClient().auth.signOut();
        if (error) {
            errorMessage = error.message;
            working = false;
            return;
        }
        await goto('/login');
    }
</script>


<svelte:head>
    <title>{t.page_title} — DeepMap</title>
    <meta name="description" content={t.page_description} />
</svelte:head>

<main class="profile-page">

    <div class="profile-container">

        <!-- VOLTAR AO MAPA -->

        <div class="top-navigation">
            <a href="/" class="back-link">{t.back_map}</a>
            <select
                class="profile-language"
                value={currentLanguage}
                onchange={changeLanguage}
                aria-label={t.language}
            >
                <option value="en">EN</option>
                <option value="pt">PT</option>
            </select>
        </div>

        <section class="profile-card">

            <img
                src="/brand/logo.png"
                alt="DeepMap"
                class="brand-logo"
            />

            {#if checkingSession}

                <div class="status-message">
                    {t.loading}
                </div>

            {:else if !user}

                <!-- SEM SESSÃO -->

                <div class="avatar fallback-avatar">
                    <span>?</span>
                </div>

                <h1>{t.page_title}</h1>

                <p class="description">
                    {t.sign_in_prompt}
                </p>

                {#if errorMessage}
                    <p class="error-message" role="alert">
                        {errorMessage}
                    </p>
                {/if}

                <a
                    href="/login?next=%2Fprofile"
                    class="primary-link"
                >
                    {t.sign_in}
                </a>

            {:else}

                <!-- PERFIL AUTENTICADO -->

                <div class="profile-heading">

                    <!--
                        A PRÓPRIA IMAGEM É O BOTÃO.
                        O LÁPIS FAZ PARTE DO MESMO BOTÃO.
                    -->

                    <button
                        type="button"
                        class="avatar avatar-trigger"
                        onclick={openAvatarModal}
                        aria-label={t.edit_avatar}
                        title={t.edit_avatar}
                        disabled={working}
                    >
                        {#if avatarUrl && !avatarFailed}

                            <img
                                src={avatarUrl}
                                alt=""
                                referrerpolicy="no-referrer"
                                onerror={() => avatarFailed = true}
                            />

                        {:else}

                            <span>{initial}</span>

                        {/if}

                        <span
                            class="avatar-edit-badge"
                            aria-hidden="true"
                        >
                            ✎
                        </span>

                    </button>

                    <!-- Nome editável junto ao título, sem linha duplicada -->
                    <div class="profile-name-line">
                        {#if editingName}
                            <form class="name-form heading-name-form" onsubmit={saveDisplayName}>
                                <label for="profile-display-name" class="visually-hidden">
                                    {t.display_name}
                                </label>
                                <input
                                    id="profile-display-name"
                                    type="text"
                                    bind:value={nameInput}
                                    minlength="2"
                                    maxlength={MAX_DISPLAY_NAME}
                                    autocomplete="nickname"
                                    required
                                    disabled={working}
                                />
                                <div class="name-buttons">
                                    <button type="submit" class="save-name-button" disabled={working}>
                                        {working ? t.saving : t.save}
                                    </button>
                                    <button
                                        type="button"
                                        class="cancel-name-button"
                                        onclick={cancelEditingName}
                                        disabled={working}
                                    >
                                        {t.cancel}
                                    </button>
                                </div>
                            </form>
                        {:else}
                            <h1>{displayName}</h1>
                            <button
                                type="button"
                                class="heading-name-edit"
                                onclick={startEditingName}
                                aria-label={`${t.edit} — ${t.display_name}`}
                                title={`${t.edit} — ${t.display_name}`}
                                disabled={working}
                            >
                                <span aria-hidden="true">✎</span>
                            </button>
                        {/if}
                    </div>

                    <!-- @USERNAME PÚBLICO (o email permanece privado) -->
                    <div class="username-area">
                        {#if usernameLoading}
                            <span class="username-muted">{t.username_loading}</span>
                        {:else if usernameLoadError}
                            <div class="username-load-error" role="alert">
                                <span>{usernameLoadError}</span>
                                <button type="button" class="username-retry" onclick={() => void loadUsername(user.id)}>
                                    {t.retry}
                                </button>
                            </div>
                        {:else if editingUsername}
                            
                                <form class="username-form" onsubmit={saveUsername} novalidate>
                                <label for="profile-username" class="username-label">{t.username_label}</label>
                                <div class="username-input-wrap">
                                    <span aria-hidden="true">@</span>
                                    <input
                                        id="profile-username"
                                        type="text"
                                        value={usernameInput}
                                        oninput={handleUsernameInput}
                                        maxlength="20"
                                        autocapitalize="none"
                                        autocomplete="off"
                                        spellcheck="false"
                                        disabled={working}
                                    />
                                </div>
                                <span class="username-hint">{t.username_hint}</span>
                                {#if usernameStatusMessage}
                                    <span class:username-positive={usernameCheckStatus === 'available'}
                                        class:username-negative={usernameCheckStatus === 'taken' || usernameCheckStatus === 'invalid' || usernameCheckStatus === 'reserved' || usernameCheckStatus === 'check_error'}
                                        class="username-feedback" aria-live="polite">
                                        {usernameStatusMessage}
                                    </span>
                                {/if}
                                {#if usernameError}
                                    <span class="username-feedback username-negative" role="alert">{usernameError}</span>
                                {/if}
                                <div class="name-buttons username-actions">
                                    <button type="submit" class="save-name-button" disabled={working || usernameCheckStatus === 'taken' || usernameCheckStatus === 'reserved' || usernameCheckStatus === 'invalid'}>
                                        {working ? t.saving : t.save}
                                    </button>
                                    <button type="button" class="cancel-name-button" onclick={cancelEditingUsername} disabled={working}>
                                        {t.cancel}
                                    </button>
                                </div>
                            </form>
                        {:else}
                            <div class="username-display">
                                <span class:username-muted={!username} class="username-handle">
                                    {username ? `@${username}` : t.username_not_set}
                                </span>
                                <button type="button" class="username-edit-button" onclick={startEditingUsername}
                                    aria-label={`${t.edit} — ${t.username_label}`}
                                    title={`${t.edit} — ${t.username_label}`}
                                    disabled={working}>
                                    <span aria-hidden="true">✎</span>
                                </button>
                            </div>
                        {/if}
                    </div>

                    <span class="account-badge">
                        {t.account_badge}
                    </span>

                </div>

                <!-- INFORMAÇÕES DO PERFIL -->

                <div class="profile-details">

                    <!-- BIOGRAFIA CURTA (NO FUTURO: PERFIL PÚBLICO) -->
                    <div class="detail-row bio-detail-row">
                        <span class="detail-label">{t.about_me}</span>

                        {#if editingBio}
                            <form class="bio-form" onsubmit={saveBio}>
                                <label for="profile-bio" class="visually-hidden">{t.about_me}</label>
                                <textarea
                                    id="profile-bio"
                                    bind:value={bioInput}
                                    maxlength={MAX_BIO_LENGTH}
                                    placeholder={t.about_placeholder}
                                    rows="4"
                                    disabled={working}
                                ></textarea>
                                <span class="bio-count">{bioInput.length}/{MAX_BIO_LENGTH}</span>
                                <div class="name-buttons">
                                    <button type="submit" class="save-name-button" disabled={working}>
                                        {working ? t.saving : t.save}
                                    </button>
                                    <button type="button" class="cancel-name-button" onclick={cancelEditingBio} disabled={working}>
                                        {t.cancel}
                                    </button>
                                </div>
                            </form>
                        {:else}
                            <div class="bio-value">
                                <p class:bio-empty={!bio}>{bio || t.about_empty}</p>
                                <button type="button" class="edit-name-button" onclick={startEditingBio} disabled={working}>
                                    {t.edit}
                                </button>
                            </div>
                        {/if}
                    </div>
                    <p class="bio-note">{t.about_note}</p>

                    <!-- EMAIL -->

                    <div class="detail-row">

                        <span class="detail-label">
                            Email
                        </span>

                        <strong class="email-value">
                            {user.email || t.unavailable}
                        </strong>

                    </div>

                    <!-- MÉTODO DE REGISTO -->

                    <div class="detail-row">

                        <span class="detail-label">
                            {t.sign_in_method}
                        </span>

                        <strong>
                            {user.app_metadata?.provider === 'google'
                                ? 'Google'
                                : 'Email'}
                        </strong>

                    </div>

                </div>

                <!-- ==================================
                     MODAL DE AVATARES
                     ================================== -->

                <dialog
                    bind:this={avatarDialog}
                    class="avatar-dialog"
                    aria-labelledby="avatar-modal-title"
                    onclose={resetAvatarModal}
                    oncancel={(event) => {
                        if (working) event.preventDefault();
                    }}
                >

                    <div class="avatar-dialog-header">

                        <div>
                            <h2 id="avatar-modal-title">
                                {t.choose_avatar}
                            </h2>

                            <p class="avatar-help">
                                {t.choose_avatar_help}
                            </p>
                        </div>

                        <button
                            type="button"
                            class="avatar-close-button"
                            onclick={closeAvatarModal}
                            aria-label={t.close_without_saving}
                            disabled={working}
                        >
                            ×
                        </button>

                    </div>

                    <!-- SEIS AVATARES OFICIAIS -->

                    <div class="avatar-options">

                        {#each AVATAR_PRESETS as preset (preset.id)}

                            <button
                                type="button"
                                class="avatar-option"
                                class:selected={pendingAvatarChoice === preset.id}
                                aria-pressed={pendingAvatarChoice === preset.id}
                                onclick={() => selectAvatar(preset.id)}
                                disabled={working}
                                title={preset.label}
                            >

                                <span
                                    class="avatar-option-art"
                                    aria-hidden="true"
                                >

                                    {#if preset.image}

                                        <img
                                            src={preset.image}
                                            alt=""
                                            loading="lazy"
                                        />

                                    {:else}

                                        {preset.symbol}

                                    {/if}

                                </span>

                                <span class="avatar-option-label">
                                    {preset.label}
                                </span>

                            </button>

                        {/each}

                    </div>

                    <!-- FOTOGRAFIA GOOGLE -->

                    {#if googleAvatarUrl}

                        <div class="avatar-alternatives">

                            <button
                                type="button"
                                class="avatar-alternative"
                                class:selected={pendingAvatarChoice === 'google'}
                                aria-pressed={pendingAvatarChoice === 'google'}
                                onclick={() => selectAvatar('google')}
                                disabled={working}
                            >

                                <img
                                    src={googleAvatarUrl}
                                    alt=""
                                    referrerpolicy="no-referrer"
                                />

                                {t.google_photo}

                            </button>

                        </div>

                    {/if}

                    <!-- AVATAR PERSONALIZADO JÁ GUARDADO -->
                    {#if customAvatarUrl}
                        <div class="avatar-alternatives">
                            <button
                                type="button"
                                class="avatar-alternative"
                                class:selected={pendingAvatarChoice === 'custom' && !pendingAvatarFile}
                                aria-pressed={pendingAvatarChoice === 'custom' && !pendingAvatarFile}
                                onclick={() => selectAvatar('custom')}
                                disabled={working || processingFile}
                            >
                                <img src={customAvatarUrl} alt="" />
                                {t.custom_avatar}
                            </button>
                        </div>
                    {/if}

                    <!-- UPLOAD PRIVADO POR UTILIZADOR; IMAGEM PÚBLICA NO PERFIL -->
                    <div class="avatar-upload-area">
                        <label for="profile-avatar-file" class="avatar-upload-label">
                            {t.upload_avatar}
                        </label>
                        <input
                            id="profile-avatar-file"
                            class="avatar-file-input"
                            bind:this={avatarFileInput}
                            type="file"
                            accept="image/png,image/jpeg,image/webp"
                            onchange={handleAvatarFile}
                            disabled={working || processingFile}
                        />
                        <label
                            for="profile-avatar-file"
                            class="avatar-upload-button"
                            class:is-disabled={working || processingFile}
                        >
                            <span aria-hidden="true">↑</span>
                            {t.choose_image}
                        </label>
                        {#if pendingAvatarFilename}
                            <p class="avatar-selected-file" title={pendingAvatarFilename}>
                                {pendingAvatarFilename}
                            </p>
                        {/if}
                        <p class="avatar-upload-hint">{t.upload_hint}</p>

                        {#if processingFile}
                            <p class="avatar-upload-hint">{t.processing_image}</p>
                        {:else if pendingAvatarPreview}
                            <button
                                type="button"
                                class="avatar-alternative avatar-preview-button"
                                class:selected={pendingAvatarChoice === 'custom'}
                                aria-pressed={pendingAvatarChoice === 'custom'}
                                onclick={() => pendingAvatarChoice = 'custom'}
                                disabled={working}
                            >
                                <img src={pendingAvatarPreview} alt="" />
                                {t.image_preview}
                            </button>
                        {/if}
                    </div>

                    <!-- ERRO DO MODAL -->

                    {#if avatarModalError}

                        <p class="error-message" role="alert">
                            {avatarModalError}
                        </p>

                    {/if}

                    <!-- GUARDAR / CANCELAR -->

                    <div class="avatar-dialog-actions">

                        <button
                            type="button"
                            class="avatar-cancel-button"
                            onclick={closeAvatarModal}
                            disabled={working}
                        >
                            {t.cancel}
                        </button>

                        <button
                            type="button"
                            class="avatar-save-button"
                            onclick={saveAvatar}
                            disabled={working || processingFile || !canSaveAvatar}
                        >
                            {working
                                ? t.avatar_saving
                                : t.save_avatar}
                        </button>

                    </div>

                </dialog>

                <!-- MENSAGENS -->

                {#if errorMessage}

                    <p class="error-message" role="alert">
                        {errorMessage}
                    </p>

                {/if}

                {#if successMessage}

                    <p class="success-message" role="status">
                        {successMessage}
                    </p>

                {/if}

                <!-- LOGOUT -->

                <button
                    type="button"
                    class="logout-button"
                    onclick={logout}
                    disabled={working}
                >
                    {working
                        ? t.logging_out
                        : t.log_out}
                </button>

            {/if}

        </section>

    </div>

</main>

<style>
    /* ==========================================
       PÁGINA
       ========================================== */

    .profile-page {
        min-height: 100vh;
        min-height: 100dvh;
        width: 100%;
        box-sizing: border-box;

        display: flex;
        justify-content: center;

        padding: 35px 20px 50px;

        background: #0b0b0e;
        color: #e0e0e0;

        font-family: 'Segoe UI', Arial, sans-serif;
    }

    .profile-container {
        width: 100%;
        max-width: 640px;
    }

    .top-navigation {
        margin-bottom: 20px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
    }

    .profile-language {
        padding: 5px 8px;
        border: 1px solid #454550;
        border-radius: 6px;
        background: #22222a;
        color: #c8a355;
        font: inherit;
        font-size: 0.85rem;
        cursor: pointer;
    }

    .back-link {
        color: #c8a355;
        text-decoration: none;
        font-size: 0.9rem;
    }

    .back-link:hover {
        text-decoration: underline;
    }

    .profile-card {
        width: 100%;
        box-sizing: border-box;
        padding: 35px;

        background: #16161a;
        border: 1px solid #333340;
        border-radius: 14px;

        text-align: center;
    }

    .brand-logo {
        display: block;
        width: auto;
        max-width: 150px;
        height: auto;
        max-height: 65px;
        object-fit: contain;
        margin: 0 auto 28px;
    }

    .status-message {
        color: #a0a0aa;
        padding: 40px 0;
    }

    /* ==========================================
       AVATAR PRINCIPAL
       ========================================== */

    .profile-heading {
        display: flex;
        flex-direction: column;
        align-items: center;
    }

    .avatar {
        width: 100px;
        height: 100px;

        display: flex;
        align-items: center;
        justify-content: center;

        margin: 0 auto 15px;

        border-radius: 50%;
        border: 3px solid #c8a355;

        background: #292933;
        color: #c8a355;

        overflow: hidden;

        font-size: 2.5rem;
        font-weight: 700;
    }

    .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
    }

    .avatar-trigger {
        position: relative;
        padding: 0;
        font: inherit;
        cursor: pointer;

        transition:
            border-color 0.2s,
            box-shadow 0.2s;
    }

    .avatar-trigger:hover {
        border-color: #eed18a;
        box-shadow: 0 0 0 4px rgba(200, 163, 85, 0.15);
    }

    .avatar-trigger:focus-visible {
        outline: 2px solid #c8a355;
        outline-offset: 4px;
    }

    .avatar-trigger:disabled {
        opacity: 0.7;
        cursor: wait;
    }

    .avatar-edit-badge {
        position: absolute;
        right: 3px;
        bottom: 3px;

        display: flex;
        align-items: center;
        justify-content: center;

        width: 27px;
        height: 27px;
        box-sizing: border-box;

        border: 2px solid #16161a;
        border-radius: 50%;

        background: #c8a355;
        color: #171717;

        font-size: 0.9rem;
        line-height: 1;
    }

    /* ==========================================
       NOME E IDENTIFICAÇÃO
       ========================================== */

    h1 {
        margin: 0;
        font-size: 1.65rem;
        color: #fff;
        overflow-wrap: anywhere;
    }

    .profile-name-line {
        display: flex;
        align-items: center;
        justify-content: center;
        flex-wrap: wrap;
        gap: 8px;
        max-width: 100%;
        margin: 5px 0 12px;
    }

    .heading-name-edit {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 31px;
        height: 31px;
        flex: none;
        border: 1px solid #60533e;
        border-radius: 7px;
        background: #292933;
        color: #c8a355;
        font-size: 1.1rem;
        cursor: pointer;
    }

    .heading-name-edit:hover { border-color: #c8a355; background: #353039; }
    .heading-name-edit:focus-visible { outline: 2px solid #c8a355; outline-offset: 3px; }
    .heading-name-edit:disabled { opacity: 0.6; cursor: wait; }

    .heading-name-form { width: min(100%, 340px); text-align: left; }
    .heading-name-form .name-buttons { justify-content: center; }

    /* @username público sob o nome. */
    .username-area {
        width: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        margin: 0 0 13px;
        min-width: 0;
    }
    .username-display { display: flex; align-items: center; gap: 8px; max-width: 100%; }
    .username-handle {
        font-size: 0.92rem;
        color: #c8a355;
        font-weight: 650;
        overflow-wrap: anywhere;
    }
    .username-muted { color: #92929e; font-size: 0.85rem; }
    .username-edit-button {
        flex: none;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 27px;
        height: 27px;
        border: 1px solid #60533e;
        border-radius: 6px;
        background: #292933;
        color: #c8a355;
        cursor: pointer;
    }
    .username-edit-button:hover { border-color: #c8a355; }
    .username-edit-button:focus-visible { outline: 2px solid #c8a355; outline-offset: 3px; }
    .username-edit-button:disabled { opacity: 0.55; cursor: wait; }
    .username-form {
        width: min(100%, 300px);
        display: flex;
        flex-direction: column;
        gap: 9px;
        text-align: left;
    }
    .username-label { font-size: 0.83rem; color: #bdbdc6; }
    .username-input-wrap {
        display: flex;
        align-items: center;
        gap: 7px;
        padding: 0 12px;
        border: 1px solid #525264;
        border-radius: 6px;
        background: #22222a;
        color: #c8a355;
    }
    .username-input-wrap:focus-within { outline: 2px solid #c8a355; outline-offset: 2px; }
    .username-input-wrap input {
        min-width: 0;
        width: 100%;
        padding: 10px 0;
        border: 0;
        outline: none;
        background: transparent;
        color: #fff;
        font: inherit;
        font-size: 0.9rem;
    }
    .username-hint { color: #92929e; font-size: 0.76rem; line-height: 1.5; }
    .username-feedback { font-size: 0.81rem; color: #bfc0cc; }
    .username-positive { color: #9ee0ac; }
    .username-negative { color: #ff8585; }
    .username-actions { justify-content: center; }
    .username-load-error { display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 8px; color: #ff8585; font-size: 0.82rem; }
    .username-retry { background: #292933; color: #c8a355; border: 1px solid #60533e; border-radius: 6px; padding: 5px 9px; cursor: pointer; }

    .account-badge {
        display: inline-block;
        padding: 6px 12px;

        border: 1px solid #5c4b2c;
        border-radius: 20px;

        background: #29251b;
        color: #c8a355;

        font-size: 0.75rem;
        font-weight: 700;
    }

    .description {
        color: #a0a0aa;
        line-height: 1.6;
    }

    /* ==========================================
       DADOS DO PERFIL
       ========================================== */

    .profile-details {
        margin-top: 32px;

        border: 1px solid #333340;
        border-radius: 9px;

        overflow: hidden;
        text-align: left;
    }

    .detail-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 15px;

        padding: 17px 18px;
        border-bottom: 1px solid #333340;
    }

    .detail-row:last-child {
        border-bottom: none;
    }

    .detail-label {
        color: #a0a0aa;
        font-size: 0.85rem;
    }

    .detail-row strong {
        font-size: 0.9rem;
        text-align: right;
        overflow-wrap: anywhere;
        min-width: 0;
    }

    .email-value {
        color: #c8a355;
    }

    .name-form {
        width: min(100%, 260px);

        display: flex;
        flex-direction: column;
        gap: 9px;
    }

    .name-form input {
        width: 100%;
        box-sizing: border-box;

        padding: 10px 12px;
        border: 1px solid #525264;
        border-radius: 6px;

        background: #22222a;
        color: #fff;

        font: inherit;
        font-size: 0.9rem;
    }

    .name-form input:focus-visible {
        outline: 2px solid #c8a355;
        outline-offset: 2px;
    }

    .name-buttons {
        display: flex;
        gap: 8px;
    }

    .edit-name-button,
    .save-name-button,
    .cancel-name-button {
        padding: 7px 11px;

        border: 1px solid #c8a355;
        border-radius: 6px;

        background: #292933;
        color: #c8a355;

        font: inherit;
        font-size: 0.8rem;
        cursor: pointer;
    }

    .save-name-button {
        background: #c8a355;
        color: #171717;
        font-weight: 700;
    }

    .cancel-name-button {
        border-color: #454550;
        color: #d0d0d4;
    }

    .edit-name-button:disabled,
    .save-name-button:disabled,
    .cancel-name-button:disabled {
        opacity: 0.6;
        cursor: wait;
    }

    .visually-hidden {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
    }

    /* BIOGRAFIA: conteúdo textual simples, sem HTML. */
    .bio-detail-row { align-items: flex-start; }
    .bio-value { min-width: 0; flex: 1; display: flex; align-items: flex-start; justify-content: flex-end; gap: 14px; }
    .bio-value p { margin: 0; max-width: 290px; color: #e0e0e0; line-height: 1.5; white-space: pre-wrap; overflow-wrap: anywhere; font-size: 0.9rem; }
    .bio-value .bio-empty { color: #92929e; font-style: italic; }
    .bio-note { margin: 0; padding: 10px 18px; color: #92929e; font-size: 0.76rem; line-height: 1.4; border-bottom: 1px solid #333340; }
    .bio-form { width: min(100%, 320px); display: flex; flex-direction: column; gap: 9px; }
    .bio-form textarea { width: 100%; box-sizing: border-box; resize: vertical; min-height: 92px; padding: 11px; border: 1px solid #525264; border-radius: 6px; background: #22222a; color: #fff; font: inherit; font-size: 0.9rem; }
    .bio-form textarea:focus-visible { outline: 2px solid #c8a355; outline-offset: 2px; }
    .bio-count { text-align: right; font-size: 0.76rem; color: #92929e; }

    /* ==========================================
       MENSAGENS E LOGOUT
       ========================================== */

    .success-message {
        color: #9ee0ac;
        font-size: 0.85rem;
    }

    .error-message {
        color: #ff8585;
        font-size: 0.85rem;
    }

    .logout-button {
        width: 100%;
        margin-top: 25px;
        padding: 13px;

        border: 1px solid #454550;
        border-radius: 7px;

        background: #292933;
        color: #fff;

        font: inherit;
        font-weight: 600;
        cursor: pointer;
    }

    .logout-button:hover {
        background: #363640;
    }

    .logout-button:disabled {
        opacity: 0.6;
        cursor: wait;
    }

    .primary-link {
        display: block;
        margin-top: 25px;
        padding: 13px;

        border-radius: 7px;

        background: #c8a355;
        color: #171717;

        text-decoration: none;
        font-weight: 700;
    }

    /* ==========================================
       MODAL DE AVATARES
       ========================================== */

    .avatar-dialog {
        width: min(540px, calc(100% - 28px));
        max-width: 540px;
        max-height: calc(100dvh - 32px);

        box-sizing: border-box;
        margin: auto;
        padding: 24px;
        overflow-y: auto;

        border: 1px solid #615032;
        border-radius: 14px;

        background: #16161a;
        color: #e0e0e0;

        box-shadow: 0 20px 80px rgba(0, 0, 0, 0.65);

        text-align: left;
        font-family: inherit;
    }

    .avatar-dialog::backdrop {
        background: rgba(0, 0, 0, 0.78);
        backdrop-filter: blur(3px);
    }

    .avatar-dialog-header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 15px;
        margin-bottom: 20px;
    }

    .avatar-dialog h2 {
        margin: 0 0 7px;
        color: #f3f0e7;
        font-size: 1.18rem;
    }

    .avatar-help {
        margin: 0;
        color: #a0a0aa;
        font-size: 0.85rem;
        line-height: 1.5;
    }

    .avatar-close-button {
        flex: none;

        width: 34px;
        height: 34px;

        border: 1px solid #454550;
        border-radius: 7px;

        background: #292933;
        color: #e0e0e0;

        font-size: 1.5rem;
        line-height: 1;
        cursor: pointer;
    }

    /* GRELHA DOS SEIS AVATARES */

    .avatar-options {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 10px;
    }

    .avatar-option {
        min-width: 0;

        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;

        padding: 12px 5px 10px;

        border: 1px solid #454550;
        border-radius: 10px;

        background: #222229;
        color: #e2e2e7;

        font: inherit;
        cursor: pointer;
    }

    .avatar-option-art {
        display: flex;
        align-items: center;
        justify-content: center;

        width: 78px;
        height: 78px;
        max-width: calc(100% - 8px);
        aspect-ratio: 1;

        overflow: hidden;

        border: 2px solid #65563c;
        border-radius: 50%;

        background: #30303a;
        color: #c8a355;

        font-size: 1.05rem;
        font-weight: 800;
        letter-spacing: 0.04em;
    }

    .avatar-option-art img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
    }

    .avatar-option-label {
        font-size: 0.75rem;
        text-align: center;
        overflow-wrap: anywhere;
    }

    .avatar-option.selected,
    .avatar-alternative.selected {
        background: #302a1e;
        border-color: #c8a355;
        box-shadow: inset 0 0 0 1px #c8a355;
    }

    /* FOTOGRAFIA GOOGLE */

    .avatar-alternatives {
        display: flex;
        flex-wrap: wrap;
        gap: 9px;
        margin-top: 14px;
    }

    .avatar-alternative {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 9px;

        min-height: 44px;
        padding: 7px 11px;

        border: 1px solid #454550;
        border-radius: 8px;

        background: #222229;
        color: #e2e2e7;

        font: inherit;
        font-size: 0.82rem;
        cursor: pointer;
    }

    .avatar-alternative img {
        width: 29px;
        height: 29px;
        border-radius: 50%;
        object-fit: cover;
    }

    /* UPLOAD DE IMAGEM PERSONALIZADA */
    .avatar-upload-area {
        margin-top: 17px;
        padding: 15px;
        border: 1px dashed #60533e;
        border-radius: 9px;
        background: #202027;
    }
    .avatar-upload-label { display: block; margin-bottom: 9px; color: #c8a355; font-size: 0.86rem; font-weight: 700; }
    /* O input continua acessível, mas a apresentação fica 100% traduzível. */
    .avatar-file-input {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip-path: inset(50%);
        white-space: nowrap;
        border: 0;
    }
    .avatar-upload-button {
        display: inline-flex;
        align-items: center;
        gap: 9px;
        max-width: 100%;
        box-sizing: border-box;
        padding: 10px 14px;
        border: 1px solid #66573e;
        border-radius: 7px;
        background: #32303a;
        color: #f2f0eb;
        font: inherit;
        font-size: 0.85rem;
        font-weight: 600;
        cursor: pointer;
    }
    .avatar-upload-button:hover { border-color: #c8a355; }
    .avatar-upload-button.is-disabled { opacity: 0.55; cursor: wait; }
    .avatar-file-input:focus-visible + .avatar-upload-button {
        outline: 2px solid #c8a355;
        outline-offset: 3px;
    }
    .avatar-selected-file {
        max-width: 100%;
        margin: 10px 0 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        color: #d0d0d8;
        font-size: 0.8rem;
    }
    .avatar-upload-hint { margin: 9px 0 0; color: #a0a0aa; font-size: 0.76rem; line-height: 1.5; }
    .avatar-preview-button { margin-top: 12px; }

    /* BOTÕES DO MODAL */

    .avatar-dialog-actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;

        margin-top: 24px;
        padding-top: 18px;

        border-top: 1px solid #333340;
    }

    .avatar-cancel-button,
    .avatar-save-button {
        min-width: 116px;
        padding: 11px 14px;

        border: 1px solid #454550;
        border-radius: 7px;

        background: #292933;
        color: #e0e0e0;

        font: inherit;
        font-size: 0.85rem;
        font-weight: 700;
        cursor: pointer;
    }

    .avatar-save-button {
        border-color: #c8a355;
        background: #c8a355;
        color: #171717;
    }

    .avatar-option:disabled,
    .avatar-alternative:disabled,
    .avatar-cancel-button:disabled,
    .avatar-save-button:disabled,
    .avatar-close-button:disabled {
        opacity: 0.55;
        cursor: wait;
    }

    .avatar-option:focus-visible,
    .avatar-alternative:focus-visible,
    .avatar-cancel-button:focus-visible,
    .avatar-save-button:focus-visible,
    .avatar-close-button:focus-visible {
        outline: 2px solid #c8a355;
        outline-offset: 3px;
    }

    /* ==========================================
       MOBILE
       ========================================== */

    @media (max-width: 600px) {

        .profile-page {
            padding: 18px 12px 35px;
        }

        .profile-card {
            padding: 25px 17px;
        }

        .detail-row {
            align-items: flex-start;
            flex-direction: column;
            gap: 7px;
        }

        .detail-row strong {
            text-align: left;
        }

        .name-form, .bio-form { width: 100%; }
        .bio-value { justify-content: flex-start; width: 100%; }

        .avatar {
            width: 85px;
            height: 85px;
        }
    }

    @media (max-width: 440px) {

        .avatar-dialog {
            padding: 18px 12px;
        }

        .avatar-options {
            gap: 7px;
        }

        .avatar-option {
            padding: 9px 3px;
        }

        .avatar-option-art {
            width: 64px;
            height: 64px;
        }

        .avatar-dialog-actions {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .avatar-cancel-button,
        .avatar-save-button {
            min-width: 0;
        }
    }

    
/* Upload de avatar — conteúdo centrado */

.avatar-upload-area {
    text-align: center;
}

.avatar-upload-button {
    justify-content: center;
}


/* Mensagens de erro no modal de avatares */

.avatar-dialog .error-message {
    text-align: center;
    width: 100%;
    box-sizing: border-box;
}


</style>
