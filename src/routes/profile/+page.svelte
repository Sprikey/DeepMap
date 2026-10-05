<script>
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, setSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
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
    let signingOut = $state(false); // Manter o perfil intacto até a navegação terminar.
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
    let usernameChangedAt = $state(null);
    let usernameIsGenerated = $state(false);
    // A privacidade do perfil é guardada na coluna public.profiles.is_public.
    let profileIsPublic = $state(true);
    let privacySaving = $state(false);
    let privacyError = $state('');
    let privacySuccess = $state('');
    let usernameLoading = $state(true);
    let usernameLoadError = $state('');
    let editingUsername = $state(false);
    // O aviso de bloqueio só aparece depois de o utilizador carregar no lápis.
    let usernameCooldownNotice = $state(false);
    let usernameInput = $state('');
    let usernameError = $state('');
    let usernameCheckStatus = $state('idle');
    let usernameUserId = null;
    let usernameLoadVersion = 0;
    let usernameCheckVersion = 0;
    let usernameCheckTimer = null;
    // Feedback local do botão de partilha no cabeçalho.
    let profileLinkStatus = $state('');
    let profileLinkFeedbackTimer = null;

    // O bloqueio é imposto pelo trigger no Supabase. Aqui apenas o apresentamos.
    let usernameAvailableAfter = $derived(
        usernameChangedAt
            ? new Date(new Date(usernameChangedAt).getTime() + 30 * 24 * 60 * 60 * 1000)
            : null
    );
    let usernameOnCooldown = $derived(
        !usernameIsGenerated && usernameAvailableAfter !== null && Date.now() < usernameAvailableAfter.getTime()
    );
    let usernameNextChangeText = $derived(
        usernameAvailableAfter
            ? new Intl.DateTimeFormat(currentLanguage === 'pt' ? 'pt-PT' : 'en-GB', {
                dateStyle: 'medium', timeStyle: 'short'
            }).format(usernameAvailableAfter)
            : ''
    );

    let usernameStatusMessage = $derived({
        checking: t.username_checking,
        available: t.username_available,
        taken: t.username_taken,
        held: t.username_held,
        invalid: t.username_format_error,
        reserved: t.username_reserved,
        check_error: t.username_check_error
    }[usernameCheckStatus] ?? '');

    let memberSinceYear = $derived(
        user?.created_at && !Number.isNaN(Date.parse(user.created_at))
            ? new Date(user.created_at).getFullYear()
            : null
    );

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

    // Modo único de edição do perfil.
    let profileEditMode = $state(false);
    let settingsMenuOpen = $state(false);

    let profileUi = $derived(currentLanguage === 'pt' ? {
        editProfile: 'Editar perfil',
        saveChanges: 'Guardar alterações',
        cancel: 'Cancelar',
        overview: 'Visão geral',
        about: 'Sobre',
        memberSince: 'Membro desde',
        permanentLink: 'Link do perfil',
        worldFaction: 'Facção DeepMap World',
        comingSoon: 'Indisponível por agora',
        banner: 'Banner do perfil',
        bannerSoon: 'Personalização do banner em breve',
        markers: 'Marcadores',
        followers: 'Seguidores',
        following: 'A seguir',
        badges: 'Badges & Títulos',
        activity: 'Atividade recente',
        editHint: 'Edita os teus dados e guarda tudo no fim.',
        saved: 'Perfil atualizado.'
    } : {
        editProfile: 'Edit profile',
        saveChanges: 'Save changes',
        cancel: 'Cancel',
        overview: 'Overview',
        about: 'About',
        memberSince: 'Member since',
        permanentLink: 'Profile link',
        worldFaction: 'DeepMap World faction',
        comingSoon: 'Unavailable for now',
        banner: 'Profile banner',
        bannerSoon: 'Banner customisation coming soon',
        markers: 'Markers',
        followers: 'Followers',
        following: 'Following',
        badges: 'Badges & Titles',
        activity: 'Recent activity',
        editHint: 'Edit your details and save everything at the end.',
        saved: 'Profile updated.'
    });

    let canSaveAvatar = $derived(
        !!pendingAvatarChoice &&
        (pendingAvatarChoice !== 'custom' || !!pendingAvatarFile || !!customAvatarUrl)
    );
    onMount(() => {
        currentLanguage = setSiteLanguage(getSiteLanguage());
        const unsubscribeLanguage = subscribeSiteLanguage((language) => { currentLanguage = language; });
        const supabase = getSupabaseBrowserClient();
        let active = true;

        async function checkSession() {
            const { data, error } = await supabase.auth.getUser();
            if (!active || signingOut) return;

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
                if (!active || signingOut || event === 'INITIAL_SESSION') return;
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
            if (profileLinkFeedbackTimer !== null) clearTimeout(profileLinkFeedbackTimer);
            unsubscribeLanguage();
            subscription.unsubscribe();
        };
    });


    function beginProfileEdit() {
        if (working || !user || usernameLoading || usernameLoadError) return;
        settingsMenuOpen = false;
        profileEditMode = true;
        editingName = true;
        editingBio = true;
        editingUsername = true;
        nameInput = displayName;
        bioInput = bio;
        usernameInput = username ?? '';
        usernameError = '';
        usernameCheckStatus = 'idle';
        errorMessage = '';
        successMessage = '';
    }

    function cancelProfileEdit() {
        if (working) return;
        profileEditMode = false;
        editingName = false;
        editingBio = false;
        editingUsername = false;
        nameInput = '';
        bioInput = '';
        usernameInput = '';
        usernameError = '';
        usernameCheckStatus = 'idle';
        usernameCooldownNotice = false;
        stopUsernameCheck();
    }

    async function saveProfileEdits(event) {
        event?.preventDefault();
        if (working || !user || usernameLoading || usernameLoadError) return;

        errorMessage = '';
        successMessage = '';
        usernameError = '';

        const cleanName = nameInput.trim().replace(/\s+/g, ' ');
        const cleanBio = bioInput.trim();
        const candidate = usernameInput.trim().toLowerCase();
        const usernameChanged = candidate !== (username ?? '');

        if (cleanName.length < 2 || cleanName.length > MAX_DISPLAY_NAME) {
            errorMessage = t.name_length_error;
            return;
        }
        if (cleanBio.length > MAX_BIO_LENGTH) {
            errorMessage = t.bio_length_error;
            return;
        }

        if (usernameChanged) {
            if (usernameOnCooldown) {
                usernameError = t.username_cooldown_error;
                usernameCooldownNotice = true;
                return;
            }
            if (!USERNAME_PATTERN.test(candidate)) {
                usernameCheckStatus = 'invalid';
                return;
            }
            if (RESERVED_USERNAMES.has(candidate)) {
                usernameCheckStatus = 'reserved';
                return;
            }
            if (usernameCheckStatus !== 'available') {
                usernameError = usernameCheckStatus === 'checking'
                    ? t.username_checking
                    : t.username_check_error;
                return;
            }
        }

        working = true;
        const supabase = getSupabaseBrowserClient();

        try {
            const metadata = {};
            if (cleanName !== displayName) metadata.display_name = cleanName;
            if (cleanBio !== bio) metadata.bio = cleanBio;

            if (Object.keys(metadata).length) {
                const { data, error } = await supabase.auth.updateUser({ data: metadata });
                if (error || !data.user) {
                    errorMessage = error?.message || t.name_save_error;
                    return;
                }
                user = data.user;
            }

            if (usernameChanged) {
                const { data: usernameRows, error } = await supabase.rpc('set_deepmap_username', {
                    p_username: candidate
                });
                const data = Array.isArray(usernameRows) ? usernameRows[0] : usernameRows;

                if (error || !data) {
                    if (error?.code === '23505') usernameCheckStatus = 'taken';
                    else if (error?.code === '23514') usernameError = t.username_format_error;
                    else if (error?.code === 'P0001' && error?.message?.includes('username_cooldown')) usernameError = t.username_cooldown_error;
                    else if (error?.code === 'P0001' && error?.message?.includes('username_temporarily_reserved')) {
                        usernameCheckStatus = 'held';
                        usernameError = t.username_held;
                    } else usernameError = t.username_save_error;
                    return;
                }

                username = data.username;
                usernameChangedAt = data.username_changed_at ?? null;
                usernameIsGenerated = data.username_is_generated === true;
            }

            profileEditMode = false;
            editingName = false;
            editingBio = false;
            editingUsername = false;
            nameInput = '';
            bioInput = '';
            usernameInput = '';
            usernameCheckStatus = 'idle';
            stopUsernameCheck();
            successMessage = profileUi.saved;
        } catch (error) {
            console.error('DeepMap profile save:', error);
            errorMessage = t.name_save_error;
        } finally {
            working = false;
        }
    }

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
        usernameChangedAt = null;
        usernameIsGenerated = false;
        profileIsPublic = true;
        privacySaving = false;
        privacyError = '';
        privacySuccess = '';
        usernameLoading = false;
        usernameLoadError = '';
        editingUsername = false;
        usernameCooldownNotice = false;
        usernameInput = '';
        usernameError = '';
        usernameCheckStatus = 'idle';
        profileLinkStatus = '';
        if (profileLinkFeedbackTimer !== null) clearTimeout(profileLinkFeedbackTimer);
        profileLinkFeedbackTimer = null;
    }

    async function loadUsername(userId) {
        const ticket = ++usernameLoadVersion;
        usernameUserId = userId;
        username = null;
        usernameChangedAt = null;
        usernameIsGenerated = false;
        profileIsPublic = true;
        privacyError = '';
        privacySuccess = '';
        usernameLoading = true;
        usernameLoadError = '';
        editingUsername = false;
        usernameCooldownNotice = false;
        stopUsernameCheck();

        try {
            const { data, error } = await getSupabaseBrowserClient()
                .from('profiles')
                .select('username, username_changed_at, username_is_generated, is_public')
                .eq('id', userId)
                .maybeSingle();

            if (ticket !== usernameLoadVersion) return;
            if (error) {
                usernameLoadError = t.username_load_error;
                return;
            }
            username = data?.username ?? null;
            usernameChangedAt = data?.username_changed_at ?? null;
            usernameIsGenerated = data?.username_is_generated === true;
            profileIsPublic = data?.is_public ?? true;
        } catch {
            if (ticket === usernameLoadVersion) usernameLoadError = t.username_load_error;
        } finally {
            if (ticket === usernameLoadVersion) usernameLoading = false;
        }
    }

    async function copyPermanentProfileLink() {
        if (!user?.id || !username || usernameLoading || usernameLoadError) return;
        const accountId = user.id;
        const url = `${window.location.origin}/p/${encodeURIComponent(accountId)}`;
        if (profileLinkFeedbackTimer !== null) clearTimeout(profileLinkFeedbackTimer);
        profileLinkFeedbackTimer = null;
        profileLinkStatus = '';

        try {
            if (navigator.clipboard?.writeText) {
                await navigator.clipboard.writeText(url);
            } else {
                // Fallback para browsers que não disponibilizam Clipboard API.
                const input = document.createElement('textarea');
                input.value = url;
                input.setAttribute('readonly', '');
                input.style.position = 'fixed';
                input.style.opacity = '0';
                document.body.appendChild(input);
                try {
                    input.select();
                    if (!document.execCommand('copy')) throw new Error('Copy unavailable');
                } finally {
                    input.remove();
                }
            }
            if (user?.id === accountId) profileLinkStatus = 'copied';
        } catch {
            if (user?.id === accountId) profileLinkStatus = 'error';
        }
        if (user?.id === accountId) {
            profileLinkFeedbackTimer = setTimeout(() => {
                profileLinkStatus = '';
                profileLinkFeedbackTimer = null;
            }, 3000);
        }
    }

    async function toggleProfileVisibility() {
        // Sem @username ainda não existe registo na tabela profiles.
        if (!user || !username || usernameLoading || usernameLoadError || privacySaving || working) return;

        const userId = user.id;
        const nextIsPublic = !profileIsPublic;
        privacySaving = true;
        privacyError = '';
        privacySuccess = '';

        try {
            const { data, error } = await getSupabaseBrowserClient()
                .from('profiles')
                .update({ is_public: nextIsPublic })
                .eq('id', userId)
                .select('is_public')
                .single();

            if (user?.id !== userId) return;
            if (error || !data || data.is_public !== nextIsPublic) {
                privacyError = t.visibility_save_error;
                return;
            }

            profileIsPublic = data.is_public;
            privacySuccess = t.visibility_saved;
        } catch {
            if (user?.id === userId) privacyError = t.visibility_save_error;
        } finally {
            privacySaving = false;
        }
    }

    function startEditingUsername() {
        if (working || !user || usernameLoading || usernameLoadError) return;
        // Mesmo durante os 30 dias, o lápis permite consultar a data de desbloqueio.
        if (usernameOnCooldown) {
            usernameCooldownNotice = !usernameCooldownNotice;
            return;
        }
        usernameCooldownNotice = false;
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
        usernameCooldownNotice = false;
        usernameInput = '';
        usernameCheckStatus = 'idle';
        usernameError = '';
    }

    async function checkUsernameAvailability(candidate, ticket) {
        if (ticket !== usernameCheckVersion || !user || !editingUsername) return;
        try {
            // A RPC considera usernames ativos E usernames libertados na última hora.
            // A validação definitiva continua no trigger do Supabase.
            const { data, error } = await getSupabaseBrowserClient()
                .rpc('username_availability', { p_username: candidate });

            if (ticket !== usernameCheckVersion || !editingUsername) return;
            if (error || !['available', 'taken', 'held'].includes(data)) {
                usernameCheckStatus = 'check_error';
                return;
            }
            usernameCheckStatus = data;
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
        if (usernameOnCooldown) { usernameError = t.username_cooldown_error; return; }
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
        if (usernameCheckStatus === 'taken' || usernameCheckStatus === 'held') return;

        stopUsernameCheck();
        working = true;
        const supabase = getSupabaseBrowserClient();

        try {
            const { data: usernameRows, error } = await supabase.rpc('set_deepmap_username', {
                p_username: candidate
            });
            const data = Array.isArray(usernameRows) ? usernameRows[0] : usernameRows;

            if (error || !data) {
                if (error?.code === '23505') {
                    usernameCheckStatus = 'taken';
                } else if (error?.code === '23514') {
                    usernameError = t.username_format_error;
                } else if (error?.code === 'P0001' && error?.message?.includes('username_cooldown')) {
                    usernameError = t.username_cooldown_error;
                } else if (error?.code === 'P0001' && error?.message?.includes('username_temporarily_reserved')) {
                    usernameCheckStatus = 'held';
                    usernameError = t.username_held;
                } else {
                    usernameError = t.username_save_error;
                }
                return;
            }

            username = data.username;
            usernameChangedAt = data.username_changed_at ?? null;
            usernameIsGenerated = data.username_is_generated === true;
            editingUsername = false;
            usernameCooldownNotice = false;
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

        // Ao terminar sessão, regressar à homepage global do DeepMap.
        const logoutDestination = '/';
        signingOut = true;
        let error;
        try {
            ({ error } = await getSupabaseBrowserClient().auth.signOut());
        } catch (caught) {
            error = caught;
        }
        if (error) {
            signingOut = false;
            errorMessage = error.message || t.session_error;
            working = false;
            return;
        }
        // SIGNED_OUT não mostra o estado de visitante neste intervalo.
        // Substituir o perfil no histórico pela homepage.
        try {
            await goto(logoutDestination, { replaceState: true });
        } catch {
            window.location.assign(logoutDestination);
        }
    }
</script>


<svelte:head>
    <title>{t.page_title} — DeepMap</title>
    <meta name="description" content={t.page_description} />
</svelte:head>

<main class="profile-page">

    <div class="profile-container">

                <section class="profile-card">

            {#if checkingSession}

                <div class="status-message" role="status" aria-live="polite">
                    <span class="profile-spinner" aria-hidden="true"></span>
                    <span class="visually-hidden">{t.loading}</span>
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

                <section class="profile-showcase">
                    <div class="profile-banner" aria-label={profileUi.banner}>
                        <div class="profile-banner-shade"></div>
                        {#if profileEditMode}
                            <button type="button" class="banner-edit-soon" disabled title={profileUi.bannerSoon}>
                                <span aria-hidden="true">✎</span>
                                {profileUi.bannerSoon}
                            </button>
                        {/if}
                    </div>

                    <div class="profile-identity-shell">
                        <div class="profile-avatar-column" class:profile-avatar-editing={profileEditMode}>
                            <button
                                type="button"
                                class="avatar profile-main-avatar"
                                class:avatar-editable={profileEditMode}
                                onclick={() => profileEditMode && openAvatarModal()}
                                aria-label={profileEditMode ? t.edit_avatar : displayName}
                                title={profileEditMode ? t.edit_avatar : displayName}
                                disabled={working || !profileEditMode}
                            >
                                {#if avatarUrl && !avatarFailed}
                                    <img src={avatarUrl} alt="" referrerpolicy="no-referrer" onerror={() => avatarFailed = true} />
                                {:else}
                                    <span>{initial}</span>
                                {/if}
                            </button>
                            {#if profileEditMode}
                                <button type="button" class="avatar-edit-chip" onclick={openAvatarModal} disabled={working}>
                                    ✎
                                </button>
                            {/if}
                        </div>

                        <div class="profile-identity-main">
                            {#if profileEditMode}
                                <form class="profile-edit-form" onsubmit={saveProfileEdits}>
                                    <p class="edit-mode-note">{profileUi.editHint}</p>

                                    <label class="edit-field">
                                        <span>{t.display_name}</span>
                                        <input
                                            type="text"
                                            bind:value={nameInput}
                                            minlength="2"
                                            maxlength={MAX_DISPLAY_NAME}
                                            autocomplete="nickname"
                                            required
                                            disabled={working}
                                        />
                                    </label>

                                    <label class="edit-field">
                                        <span>{t.username_label}</span>
                                        <div class="username-input-wrap profile-edit-username">
                                            <span aria-hidden="true">@</span>
                                            <input
                                                type="text"
                                                value={usernameInput}
                                                oninput={handleUsernameInput}
                                                maxlength="20"
                                                autocapitalize="none"
                                                autocomplete="off"
                                                spellcheck="false"
                                                disabled={working || usernameOnCooldown}
                                            />
                                        </div>
                                        {#if usernameOnCooldown}
                                            <small>{t.username_cooldown_until} {usernameNextChangeText}</small>
                                        {:else}
                                            {#if username}
                                                <small class="username-change-warning">{t.username_change_notice}</small>
                                            {/if}
                                            {#if usernameStatusMessage}
                                                <small
                                                    class:username-positive={usernameCheckStatus === 'available'}
                                                    class:username-negative={usernameCheckStatus === 'taken' || usernameCheckStatus === 'invalid' || usernameCheckStatus === 'reserved' || usernameCheckStatus === 'held' || usernameCheckStatus === 'check_error'}
                                                >{usernameStatusMessage}</small>
                                            {/if}
                                        {/if}
                                        {#if usernameError}<small class="username-negative">{usernameError}</small>{/if}
                                    </label>

                                    <label class="edit-field">
                                        <span>{t.about_me}</span>
                                        <textarea bind:value={bioInput} maxlength={MAX_BIO_LENGTH} rows="3" placeholder={t.about_placeholder} disabled={working}></textarea>
                                        <small>{bioInput.length}/{MAX_BIO_LENGTH}</small>
                                    </label>

                                    <div class="profile-edit-actions">
                                        <button type="submit" class="profile-save-button" disabled={working || processingFile}>
                                            {working ? t.saving : profileUi.saveChanges}
                                        </button>
                                        <button type="button" class="profile-cancel-button" onclick={cancelProfileEdit} disabled={working}>
                                            {profileUi.cancel}
                                        </button>
                                    </div>
                                </form>
                            {:else}
                                <div class="profile-title-row">
                                    <div>
                                        <h1>{displayName}</h1>
                                        <div class="public-handle-row">
                                            <span class:username-muted={!username} class="username-handle">
                                                {username ? `@${username}` : t.username_not_set}
                                            </span>
                                            {#if username}
                                                <button
                                                    type="button"
                                                    class="username-copy-button"
                                                    onclick={copyPermanentProfileLink}
                                                    aria-label={t.copy_profile_link}
                                                    title={t.copy_profile_link}
                                                    disabled={working || usernameLoading || !!usernameLoadError}
                                                >
                                                    <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                                        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
                                                        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
                                                    </svg>
                                                </button>
                                            {/if}
                                        </div>
                                    </div>
                                    <div class="profile-title-actions">
                                        <span class="explorer-title-badge"><span aria-hidden="true">✦</span> {t.account_badge}</span>
                                        <div class="profile-toolbar">
                                                            <details class="profile-settings" bind:open={settingsMenuOpen}>
                                                                <summary class="settings-trigger" title={t.settings_menu}>
                                                                    <svg viewBox="0 0 24 24" width="21" height="21" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                                                        <path d="M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z" />
                                                                        <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06-1.91 1.91-.06-.06A1.65 1.65 0 0 0 16 18.4a1.65 1.65 0 0 0-1 1.52V20h-2.7v-.08a1.65 1.65 0 0 0-1-1.52 1.65 1.65 0 0 0-1.82.33l-.06.06-1.91-1.91.06-.06A1.65 1.65 0 0 0 7.9 15a1.65 1.65 0 0 0-1.52-1H6.3v-2.7h.08A1.65 1.65 0 0 0 7.9 10.3a1.65 1.65 0 0 0-.33-1.82l-.06-.06 1.91-1.91.06.06A1.65 1.65 0 0 0 11.3 6.9a1.65 1.65 0 0 0 1-1.52V5.3H15v.08a1.65 1.65 0 0 0 1 1.52 1.65 1.65 0 0 0 1.82-.33l.06-.06 1.91 1.91-.06.06A1.65 1.65 0 0 0 19.4 10.3a1.65 1.65 0 0 0 1.52 1H21v2.7h-.08A1.65 1.65 0 0 0 19.4 15Z" transform="translate(-1.65 -0.65)" />
                                                                    </svg>
                                                                    <span class="visually-hidden">{t.settings_menu}</span>
                                                                </summary>
                                                                <div class="settings-menu">
                                                                    <span class="settings-eyebrow">{t.private_label}</span>
                                                                    <button
                                                                        type="button"
                                                                        class="settings-edit-profile"
                                                                        onclick={beginProfileEdit}
                                                                        disabled={working || usernameLoading || !!usernameLoadError}
                                                                    >
                                                                        <svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                                                            <path d="M12 20h9" /><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L8 18l-4 1 1-4Z" />
                                                                        </svg>
                                                                        <span>{profileUi.editProfile}</span>
                                                                    </button>
                                                                    <details class="settings-information">
                                                                        <summary>
                                                                            <svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                                                                <circle cx="12" cy="12" r="9" /><path d="M12 11v5m0-8h.01" />
                                                                            </svg>
                                                                            <span>{t.private_settings}</span>
                                                                            <span class="settings-chevron" aria-hidden="true">⌄</span>
                                                                        </summary>
                                                                        <div class="settings-information-body">
                                                                            <p>{t.private_description}</p>
                                                                            <span class="settings-detail-label">{t.email}</span>
                                                                            <strong class="email-value">{user.email || t.unavailable}</strong>
                                                                            <span class="settings-detail-label">{t.sign_in_method}</span>
                                                                            <strong>{user.app_metadata?.provider === 'google' ? 'Google' : 'Email'}</strong>
                                                                        </div>
                                                                    </details>
                                                                    <details class="settings-information settings-privacy">
                                                                        <summary>
                                                                            <svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                                                                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z" />
                                                                                <path d="M9 12l2 2 4-4" />
                                                                            </svg>
                                                                            <span>{t.privacy_settings}</span>
                                                                            <span class="settings-chevron" aria-hidden="true">⌄</span>
                                                                        </summary>
                                                                        <div class="settings-information-body">
                                                                            {#if usernameLoading}
                                                                                <p class="visibility-message" role="status">{t.visibility_loading}</p>
                                                                            {:else}
                                                                            <div class="visibility-row">
                                                                                <div class="visibility-copy">
                                                                                    <strong>{t.profile_visibility_toggle}</strong>
                                                                                    <p>{profileIsPublic ? t.visibility_public_explanation : t.visibility_private_explanation}</p>
                                                                                </div>
                                                                                <button
                                                                                    type="button"
                                                                                    class="visibility-switch"
                                                                                    class:enabled={profileIsPublic}
                                                                                    role="switch"
                                                                                    aria-label={t.profile_visibility_toggle}
                                                                                    aria-checked={profileIsPublic}
                                                                                    title={profileIsPublic ? t.visibility_public : t.visibility_private}
                                                                                    onclick={toggleProfileVisibility}
                                                                                    disabled={privacySaving || working || usernameLoading || !!usernameLoadError || !username}
                                                                                ><span class="visibility-switch-thumb" aria-hidden="true"></span></button>
                                                                            </div>
                                                                            <span class="visibility-status">{profileIsPublic ? t.visibility_public : t.visibility_private}</span>
                                                                            <p class="visibility-private-note">{t.visibility_email_private}</p>
                                                                            {#if username && !usernameLoadError}
                                                                                <a class="visitor-preview-link" href={`/u/${encodeURIComponent(username)}?view=visitor`}>
                                                                                    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                                                                        <path d="M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12Z" />
                                                                                        <circle cx="12" cy="12" r="3" />
                                                                                    </svg>
                                                                                    {t.view_as_visitor}
                                                                                </a>
                                                                                <p class="visitor-preview-note">{t.view_as_visitor_note}</p>
                                                                            {/if}
                                                                            {#if !username && !usernameLoading && !usernameLoadError}
                                                                                <p class="visibility-message">{t.visibility_requires_username}</p>
                                                                            {/if}
                                                                            {#if privacySaving}
                                                                                <p class="visibility-message" role="status">{t.visibility_saving}</p>
                                                                            {/if}
                                                                            {#if privacyError}
                                                                                <p class="visibility-message visibility-error" role="alert">{privacyError}</p>
                                                                            {/if}
                                                                            {#if privacySuccess}
                                                                                <p class="visibility-message visibility-success" role="status">{privacySuccess}</p>
                                                                            {/if}
                                                                            {/if}
                                                                        </div>
                                                                    </details>
                                                                    <button type="button" class="settings-logout" onclick={logout} disabled={working || privacySaving}>
                                                                        <svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                                                            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" /><path d="M16 17l5-5-5-5m5 5H9" />
                                                                        </svg>
                                                                        <span>{working ? t.logging_out : t.log_out}</span>
                                                                    </button>
                                                                </div>
                                                            </details>
                                                            </div>
                                    </div>
                                </div>

                                <p class:bio-empty={!bio} class="profile-public-bio">{bio || t.about_empty}</p>

                                <div class="profile-meta-row">
                                    {#if memberSinceYear}
                                        <span>
                                            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/></svg>
                                            {profileUi.memberSince} {memberSinceYear}
                                        </span>
                                    {/if}
                                </div>
                                {#if profileLinkStatus}
                                    <span class:username-negative={profileLinkStatus === 'error'} class="profile-link-feedback" role="status" aria-live="polite">
                                        {profileLinkStatus === 'copied' ? t.profile_link_copied : t.profile_link_copy_error}
                                    </span>
                                {/if}
                            {/if}
                        </div>
                    </div>

                </section>

                {#if errorMessage}
                    <p class="error-message profile-global-message" role="alert">{errorMessage}</p>
                {/if}
                {#if successMessage}
                    <p class="success-message profile-global-message" role="status">{successMessage}</p>
                {/if}

                <div class="profile-dashboard">
                    <div class="profile-dashboard-main">
                        <section class="profile-stats-grid" aria-label={t.future_statistics}>
                            <article class="profile-stat-card">
                                <span class="stat-icon">⌖</span>
                                <strong>—</strong>
                                <span>{profileUi.markers}</span>
                            </article>
                            <article class="profile-stat-card">
                                <span class="stat-icon">✧</span>
                                <strong>—</strong>
                                <span>{profileUi.followers}</span>
                            </article>
                            <article class="profile-stat-card">
                                <span class="stat-icon">↗</span>
                                <strong>—</strong>
                                <span>{profileUi.following}</span>
                            </article>
                        </section>

                        <section class="profile-panel profile-badges-panel">
                            <div class="panel-heading">
                                <div>
                                    <span class="panel-eyebrow">{profileUi.comingSoon}</span>
                                    <h2>{profileUi.badges}</h2>
                                </div>
                                <span class="planned-tag">{t.planned}</span>
                            </div>
                            <div class="badge-preview">
                                <span class="badge-preview-icon">✦</span>
                                <div>
                                    <strong>DeepMap Explorer</strong>
                                    <span>{profileUi.comingSoon}</span>
                                </div>
                            </div>
                        </section>
                    </div>

                    <section class="profile-panel profile-activity-panel">
                        <div class="panel-heading">
                            <div>
                                <span class="panel-eyebrow">{profileUi.comingSoon}</span>
                                <h2>{profileUi.activity}</h2>
                            </div>
                            <span class="planned-tag">{t.planned}</span>
                        </div>
                        <div class="activity-placeholder">
                            <span aria-hidden="true">◷</span>
                            <p>{t.community_note}</p>
                        </div>
                    </section>
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

    .profile-card {
        width: 100%;
        box-sizing: border-box;
        padding: 35px;

        background: #16161a;
        border: 1px solid #333340;
        border-radius: 14px;

        text-align: center;
    }

    .status-message {
        display: flex;
        align-items: center;
        justify-content: center;
        color: #a0a0aa;
        padding: 22px 0;
    }
    .profile-spinner {
        display: block;
        width: 20px;
        height: 20px;
        border: 2px solid rgba(200, 163, 85, .20);
        border-top-color: #c8a355;
        border-radius: 50%;
        animation: profile-spin .7s linear infinite;
    }
    @keyframes profile-spin { to { transform: rotate(360deg); } }
    @media (prefers-reduced-motion: reduce) {
        .profile-spinner { animation: none; }
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
    .username-copy-button {
        flex: none;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        border: 1px solid #60533e;
        border-radius: 6px;
        background: #292933;
        color: #c8a355;
        cursor: pointer;
    }
    .username-copy-button:hover { border-color: #c8a355; background: #353039; }
    .username-copy-button:focus-visible { outline: 2px solid #c8a355; outline-offset: 3px; }
    .username-copy-button:disabled { opacity: 0.55; cursor: wait; }
    .profile-link-feedback { display: block; margin-top: 5px; color: #a8d9b5; font-size: 0.78rem; }
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



    /* ==========================================
       V1.0.31 — EXPLORER PROFILE (visual only)
       ========================================== */
    .profile-page {
        padding: 32px 20px 64px;
        background:
            radial-gradient(ellipse 65% 24% at 50% 0%, rgba(137, 103, 45, 0.13), transparent 72%),
            #0b0b0e;
    }
    .profile-container { max-width: 1060px; }
    .profile-card {
        padding: 24px;
        border-color: #3c372e;
        background: #111115;
        border-radius: 18px;
        text-align: left;
        box-shadow: 0 28px 90px rgba(0, 0, 0, 0.22);
    }
    .profile-card > .status-message, .profile-card > .description, .profile-card > h1 { text-align: center; }
    .profile-card > .primary-link { text-align: center; }
    .explorer-hero {
        position: relative;
        overflow: hidden;
        padding: 25px 30px 29px;
        border: 1px solid #665436;
        border-radius: 14px;
        background:
            radial-gradient(ellipse 52% 110% at 100% 0%, rgba(194, 147, 70, 0.18), transparent 65%),
            radial-gradient(ellipse 60% 100% at 0% 100%, rgba(104, 83, 51, 0.15), transparent 80%),
            linear-gradient(125deg, #211d1c 0%, #19191d 58%, #17171b 100%);
    }
    .explorer-hero::after {
        content: '';
        pointer-events: none;
        position: absolute;
        width: 390px;
        height: 390px;
        right: -145px;
        top: -185px;
        border: 1px solid rgba(200,163,85,.14);
        border-radius: 50%;
        box-shadow: 0 0 0 44px rgba(200,163,85,.025), 0 0 0 88px rgba(200,163,85,.018);
    }
    .hero-topline { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; margin-bottom: 23px; }
    .account-badge { display: inline-flex; align-items: center; gap: 8px; letter-spacing: .075em; text-transform: uppercase; font-size: .68rem; }
    .account-badge span { font-size: .85rem; }
    .member-since { color: #aaa39a; font-size: .78rem; }
    .profile-heading { position: relative; z-index: 1; display: flex; flex-direction: row; align-items: center; text-align: left; gap: 24px; }
    .profile-heading .avatar { width: 112px; height: 112px; margin: 0; flex: none; border-width: 3px; border-color: #d1ad6c; box-shadow: 0 0 0 6px rgba(200, 163, 85, .065); }
    .identity-copy { min-width: 0; flex: 1; }
    .profile-name-line { margin: 0 0 3px; justify-content: flex-start; }
    .profile-name-line h1 { font-size: clamp(1.48rem, 3.5vw, 2rem); font-weight: 750; letter-spacing: -.035em; }
    .username-area { justify-content: flex-start; margin: 0; }
    .username-handle { font-size: .94rem; }
    .username-actions, .heading-name-form .name-buttons { justify-content: flex-start; }
    .hero-caption { margin: 13px 0 0; color: #a8a2a1; font-size: .87rem; line-height: 1.5; }
    .profile-content-grid { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(0, 1fr); align-items: start; gap: 16px; margin-top: 17px; }
    .profile-primary-column { display: grid; gap: 16px; min-width: 0; }
    .profile-panel { min-width: 0; padding: 22px; border: 1px solid #35343c; border-radius: 12px; background: #1a1a20; }
    .panel-heading { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; }
    .panel-eyebrow { display: block; margin-bottom: 7px; color: #a78e60; font-size: .68rem; letter-spacing: .11em; text-transform: uppercase; font-weight: 700; }
    .panel-heading h2 { margin: 0; color: #f2efeb; font-size: 1.14rem; line-height: 1.3; }
    .panel-description { margin: 12px 0 17px; color: #a8a8b4; font-size: .85rem; line-height: 1.55; }
    .visibility-tag, .planned-tag { display: inline-flex; border: 1px solid #5d5037; border-radius: 20px; padding: 5px 9px; color: #d9bd84; background: #2a241e; font-size: .69rem; white-space: nowrap; }
    .planned-tag { border-color: #464550; background: #24242b; color: #aaaab6; }
    .profile-panel .profile-details { margin-top: 0; }
    .about-panel .profile-details { border-radius: 9px; }
    .about-panel .bio-detail-row { border-bottom: 0; }
    .about-panel .bio-note { border-bottom: 0; border-top: 1px solid #333340; }
    .private-panel { background: #18181d; }
    .private-lock { width: 30px; height: 30px; display: grid; place-items: center; border: 1px solid #49444a; border-radius: 8px; color: #bba579; }
    .private-details .detail-row { flex-direction: column; align-items: flex-start; gap: 7px; padding: 14px; }
    .private-details .detail-row strong { max-width: 100%; text-align: left; font-size: .85rem; }
    .private-panel .logout-button { margin-top: 18px; }
    .community-panel { background: linear-gradient(150deg, #1b1b22, #17171c); }
    .community-stats { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 9px; }
    .community-stat { display: flex; flex-direction: column; align-items: center; gap: 5px; padding: 12px 4px; border: 1px solid #373640; border-radius: 9px; background: #212127; text-align: center; }
    .stat-mark { color: #b59b69; font-size: 1.08rem; line-height: 1; }
    .community-stat strong { color: #e9dfc5; font-size: 1.08rem; line-height: 1; }
    .community-stat span:last-child { color: #b7b6c1; font-size: .75rem; }
    .community-note { margin: 12px 0 0; color: #92929d; font-size: .74rem; line-height: 1.5; }
    .future-sections { display: flex; flex-wrap: wrap; gap: 7px; margin-top: 15px; padding-top: 14px; border-top: 1px solid #36353d; }
    .future-sections span { padding: 6px 9px; border: 1px solid #49434b; border-radius: 18px; color: #c5b9a9; font-size: .74rem; }
    .profile-card > .error-message, .profile-card > .success-message { text-align: center; }
    @media (max-width: 820px) {
        .profile-content-grid { grid-template-columns: 1fr; }
    }
    @media (max-width: 600px) {
        .profile-card { padding: 14px; }
        .explorer-hero { padding: 21px 17px 24px; }
        .profile-heading { align-items: flex-start; gap: 14px; }
        .profile-heading .avatar { width: 78px; height: 78px; }
        .hero-topline { margin-bottom: 19px; }
        .profile-panel { padding: 17px 15px; }
        .profile-name-line h1 { font-size: 1.48rem; }
        .profile-name-line { flex-wrap: nowrap; }
        .hero-caption { margin-top: 9px; font-size: .78rem; }
        .username-form { width: 100%; }
    }
    @media (max-width: 360px) {
        .profile-heading { flex-wrap: wrap; }
        .identity-copy { flex-basis: 100%; }
        .community-stat span:last-child { font-size: .68rem; }
    }


    /* v1.0.31: ajustes pedidos ao cabeçalho de explorador. */
    .explorer-hero { overflow: visible; }
    .explorer-hero::after { display: none; }
    .hero-topline { position: relative; z-index: 5; }
    .hero-topline-actions { display: flex; align-items: center; gap: 12px; margin-left: auto; }
    .profile-settings { position: relative; }
    .settings-trigger {
        display: inline-flex; align-items: center; justify-content: center;
        width: 39px; height: 39px; box-sizing: border-box;
        border: 1px solid #60533e; border-radius: 10px;
        color: #d1ad6c; background: #2b2728; cursor: pointer; list-style: none;
    }
    .settings-trigger::-webkit-details-marker,
    .settings-information > summary::-webkit-details-marker { display: none; }
    .settings-trigger:hover, .profile-settings[open] > .settings-trigger { border-color: #c8a355; background: #37302c; }
    .settings-trigger:focus-visible, .settings-information > summary:focus-visible,
    .settings-logout:focus-visible { outline: 2px solid #d1ad6c; outline-offset: 3px; }
    .settings-menu {
        position: absolute; top: calc(100% + 9px); right: 0; z-index: 20;
        width: min(320px, calc(100vw - 60px)); box-sizing: border-box;
        max-height: min(70vh, 470px); overflow-y: auto;
        padding: 14px; border: 1px solid #63523a; border-radius: 12px;
        background: #202025; box-shadow: 0 18px 42px rgba(0,0,0,.48);
        text-align: left;
    }
    .settings-eyebrow {
        display: block; margin: 0 0 10px; color: #bea16c;
        font-size: .7rem; font-weight: 700; letter-spacing: .09em; text-transform: uppercase;
    }
    .settings-information { border: 1px solid #45434c; border-radius: 8px; background: #29282f; }
    .settings-information > summary {
        display: flex; align-items: center; gap: 10px; padding: 13px 12px;
        color: #ede9df; cursor: pointer; list-style: none; font-size: .87rem; font-weight: 600;
    }
    .settings-information > summary svg { color: #d1ad6c; flex: none; }
    .settings-chevron { margin-left: auto; color: #aba5a5; font-size: 1rem; }
    .settings-information[open] .settings-chevron { transform: rotate(180deg); }
    .settings-information-body { display: flex; flex-direction: column; gap: 5px; padding: 1px 12px 14px; }
    .settings-information-body p { margin: 2px 0 10px; color: #adabb5; font-size: .77rem; line-height: 1.5; }
    .settings-detail-label { margin-top: 8px; color: #aca9b4; font-size: .72rem; }
    .settings-information-body strong { color: #f1ede6; font-size: .83rem; overflow-wrap: anywhere; }
    .settings-information-body .email-value { color: #d6b66f; }
    .settings-logout {
        display: flex; align-items: center; gap: 10px; width: 100%;
        margin-top: 9px; padding: 12px; border: 1px solid #45434c; border-radius: 8px;
        background: #29282f; color: #efeced; font: inherit; font-size: .87rem; font-weight: 600;
        cursor: pointer; text-align: left;
    }
    .settings-logout svg { color: #d1ad6c; flex: none; }
    .settings-logout:hover { border-color: #c8a355; background: #373039; }
    .settings-logout:disabled { opacity: .6; cursor: wait; }

    .avatar-edit-wrap { position: relative; flex: none; }
    .avatar-edit-wrap .avatar { margin: 0; }
    .avatar-edit-wrap .avatar-edit-badge {
        right: -9px; bottom: 3px; z-index: 2; width: 32px; height: 32px;
        padding: 0; border: 3px solid #211d1c; cursor: pointer;
        font: inherit; font-size: 1.02rem;
    }
    .avatar-edit-badge:hover { background: #eed18a; }
    .avatar-edit-badge:focus-visible { outline: 2px solid #eed18a; outline-offset: 3px; }
    .avatar-edit-badge:disabled { opacity: .6; cursor: wait; }

    .hero-bio { display: flex; gap: 10px; align-items: flex-start; margin-top: 12px; max-width: 100%; }
    .hero-bio > p { margin: 0; color: #c3bec0; font-size: .88rem; line-height: 1.55; white-space: pre-wrap; overflow-wrap: anywhere; }
    .hero-bio > p.bio-empty { color: #9e98a0; font-style: italic; }
    .hero-bio-edit {
        flex: none; display: inline-flex; align-items: center; justify-content: center;
        width: 28px; height: 28px; padding: 0; border: 1px solid #60533e;
        border-radius: 7px; background: #292933; color: #c8a355;
        font-size: 1rem; cursor: pointer;
    }
    .hero-bio-edit:hover { border-color: #c8a355; }
    .hero-bio-edit:focus-visible { outline: 2px solid #c8a355; outline-offset: 3px; }
    .hero-bio-edit:disabled { opacity: .6; cursor: wait; }
    .hero-bio-form { width: min(100%, 475px); }
    .hero-bio-form .name-buttons { justify-content: flex-start; }
    .profile-content-grid { grid-template-columns: minmax(0, 1fr); }

    @media (max-width: 600px) {
        .hero-topline { gap: 8px; }
        .hero-topline-actions { gap: 8px; }
        .member-since { font-size: .72rem; }
        .avatar-edit-wrap .avatar-edit-badge { width: 28px; height: 28px; right: -7px; bottom: -2px; }
        .hero-bio > p { font-size: .8rem; }
        .settings-menu { width: min(300px, calc(100vw - 48px)); }
    }
    .explorer-hero { overflow: hidden; }
    .explorer-hero::after {
        display: block;
        right: -145px;
        top: -185px;
        z-index: 0;
    }
    .explorer-hero > * { position: relative; z-index: 1; }
    .username-cooldown {
        color: #d1b77e;
        font-size: .76rem;
        line-height: 1.5;
        margin: 7px 0 0;
        overflow-wrap: anywhere;
    }
    .username-cooldown strong { color: #e5c894; font-weight: 650; }
    .username-change-notice {
        display: flex;
        flex-direction: column;
        gap: 5px;
        padding: 11px 12px;
        border: 1px solid rgba(200, 163, 85, .35);
        border-left: 3px solid #c8a355;
        border-radius: 6px;
        background: rgba(200, 163, 85, .07);
        color: #cfc4ae;
        font-size: .76rem;
        line-height: 1.5;
    }
    .username-change-notice strong { color: #e5c894; font-weight: 700; }
    @media (max-width: 600px) {
        .explorer-hero::after {
            width: 260px;
            height: 260px;
            right: -95px;
            top: -120px;
            box-shadow: 0 0 0 28px rgba(200,163,85,.025), 0 0 0 55px rgba(200,163,85,.018);
        }
    }


    /* v1.0.31 — interruptor real de visibilidade nas Definições. */
    .settings-privacy { margin-top: 9px; }
    .visibility-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
    .visibility-copy { min-width: 0; flex: 1; }
    .settings-information-body .visibility-copy strong { font-size: .84rem; }
    .settings-information-body .visibility-copy p { margin: 7px 0 2px; }
    .visibility-switch {
        position: relative; flex: none; width: 45px; height: 26px; padding: 2px;
        border: 1px solid #66616a; border-radius: 999px; background: #4a4851;
        cursor: pointer; transition: background .2s, border-color .2s;
    }
    .visibility-switch.enabled { background: #92733e; border-color: #c8a355; }
    .visibility-switch-thumb {
        display: block; width: 20px; height: 20px; border-radius: 50%;
        background: #f3efe7; box-shadow: 0 1px 3px rgba(0,0,0,.25);
        transition: transform .2s;
    }
    .visibility-switch.enabled .visibility-switch-thumb { transform: translateX(19px); }
    .visibility-switch:disabled { opacity: .5; cursor: not-allowed; }
    .visibility-switch:focus-visible { outline: 2px solid #d1ad6c; outline-offset: 3px; }
    .settings-information-body .visibility-status {
        align-self: flex-start; color: #d7b573; font-size: .75rem; font-weight: 700;
    }
    .settings-information-body .visibility-private-note { margin: 6px 0 0; }
    .settings-information-body .visibility-message { margin: 8px 0 0; font-size: .76rem; }
    .settings-information-body .visibility-error { color: #ffaaa8; }
    .settings-information-body .visibility-success { color: #a8dfba; }


    .visitor-preview-link { display: flex; align-items: center; justify-content: center; gap: 8px; margin-top: 13px; padding: 10px 11px; border-radius: 7px; border: 1px solid #665438; background: #332a21; color: #e7c985; font-weight: 650; font-size: .81rem; text-decoration: none; transition: background .2s, border-color .2s; }
    .visitor-preview-link svg { flex: none; }
    .visitor-preview-link:hover { background: #443521; border-color: #c8a355; }
    .visitor-preview-link:focus-visible { outline: 2px solid #c8a355; outline-offset: 3px; }
    .settings-information-body .visitor-preview-note { margin: 2px 0 0; font-size: .72rem; color: #aaa5a7; text-align: center; }

    /* ==========================================
       PROFILE REDESIGN — DeepMap cyan + gold
       ========================================== */
    :global(body) { background: #071019; }

    .profile-page {
        background:
            radial-gradient(circle at 80% -10%, rgba(16, 227, 242, .08), transparent 28rem),
            linear-gradient(180deg, #071019 0%, #0a1119 55%, #081018 100%);
    }

    .profile-container { max-width: 1180px; }

    .profile-card {
        padding: 22px;
        background: rgba(10, 16, 24, .96);
        border-color: #243443;
        border-radius: 18px;
        box-shadow: 0 24px 80px rgba(0,0,0,.24);
        text-align: left;
    }

    .settings-edit-profile {
        width: 100%;
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 11px 12px;
        margin-bottom: 9px;
        border: 1px solid rgba(16,227,242,.42);
        border-radius: 9px;
        background: rgba(16,227,242,.08);
        color: #8ff5fb;
        font: inherit;
        font-size: .84rem;
        font-weight: 700;
        cursor: pointer;
    }
    .settings-edit-profile:hover { background: rgba(16,227,242,.14); border-color: #10e3f2; }
    .settings-edit-profile:disabled { opacity: .5; cursor: default; }

    .profile-showcase {
        overflow: hidden;
        border: 1px solid #2c3d4b;
        border-radius: 16px 16px 0 0;
        background: #0d151e;
    }

    .profile-banner {
        position: relative;
        min-height: 285px;
        background:
            linear-gradient(90deg, rgba(5,12,18,.78) 0%, rgba(5,12,18,.12) 55%, rgba(5,12,18,.28) 100%),
            url('/brand/home-hero-world.webp') center 48% / cover no-repeat,
            linear-gradient(135deg, #122334, #0a121a);
    }

    .profile-banner-shade {
        position: absolute;
        inset: 0;
        background: linear-gradient(180deg, rgba(4,10,16,.06), rgba(4,10,16,.52));
        pointer-events: none;
    }

    .banner-edit-soon {
        position: absolute;
        right: 18px;
        top: 18px;
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 9px 12px;
        border: 1px solid rgba(224,182,102,.5);
        border-radius: 9px;
        background: rgba(8,15,22,.82);
        color: #d8bd86;
        font: inherit;
        font-size: .77rem;
        opacity: .82;
    }

    .profile-identity-shell {
        position: relative;
        display: grid;
        grid-template-columns: 168px minmax(0, 1fr);
        gap: 24px;
        min-height: 170px;
        padding: 0 30px 26px;
        border-top: 1px solid rgba(255,255,255,.04);
    }

    .profile-avatar-column { position: relative; width: 150px; margin-top: -72px; align-self: start; }
    .profile-main-avatar {
        width: 146px;
        height: 146px;
        margin: 0;
        border: 4px solid #d4ab5c;
        box-shadow: 0 0 0 6px #0d151e, 0 12px 30px rgba(0,0,0,.38);
        background: #172431;
        cursor: default;
    }
    .profile-main-avatar.avatar-editable { cursor: pointer; }
    .profile-main-avatar.avatar-editable:hover { border-color: #10e3f2; box-shadow: 0 0 0 6px #0d151e, 0 0 0 9px rgba(16,227,242,.16); }

    .avatar-edit-chip {
        position: absolute;
        right: -2px;
        bottom: 4px;
        width: 38px;
        height: 38px;
        display: grid;
        place-items: center;
        border: 2px solid #0d151e;
        border-radius: 50%;
        background: #10e3f2;
        color: #031116;
        font-weight: 900;
        cursor: pointer;
    }

    .profile-identity-main { min-width: 0; padding-top: 22px; }
    .profile-title-row { display: flex; align-items: flex-start; justify-content: space-between; gap: 18px; }
    .profile-title-actions { display: flex; align-items: center; justify-content: flex-end; gap: 10px; margin-left: auto; flex: none; }
    .profile-title-row h1 { margin: 0; color: #f3efe8; font-size: clamp(1.8rem, 4vw, 2.55rem); letter-spacing: -.035em; }
    .public-handle-row { display: flex; align-items: center; gap: 7px; margin-top: 3px; }
    .public-handle-row .username-handle { color: #d6b773; font-size: 1rem; font-weight: 700; }

    .explorer-title-badge {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        flex: none;
        padding: 8px 12px;
        border: 1px solid #6b5633;
        border-radius: 999px;
        background: rgba(190,145,67,.09);
        color: #dfc27e;
        font-size: .74rem;
        font-weight: 800;
        letter-spacing: .06em;
        text-transform: uppercase;
    }

    .profile-public-bio { margin: 14px 0 0; color: #d2d9df; line-height: 1.55; max-width: 730px; }
    .profile-meta-row { display: flex; flex-wrap: wrap; gap: 10px 22px; margin-top: 16px; color: #aeb9c3; font-size: .8rem; }
    .profile-meta-row span { display: inline-flex; align-items: center; gap: 7px; }
    .profile-meta-row svg { color: #d2ad63; }

    .profile-tabs {
        display: flex;
        gap: 2px;
        overflow-x: auto;
        padding: 0 18px;
        border-top: 1px solid #263746;
        background: rgba(7,14,21,.72);
    }
    .profile-tab {
        min-width: max-content;
        padding: 14px 18px 12px;
        border-bottom: 2px solid transparent;
        color: #92a1ad;
        font-size: .83rem;
        font-weight: 700;
    }
    .profile-tab.active { color: #eef6f7; border-color: #10e3f2; }
    .profile-tab.active span { color: #d7b569; }
    .profile-tab.disabled { opacity: .55; }

    .profile-global-message { margin: 14px 0 0; text-align: center; }

    .profile-dashboard {
        display: grid;
        grid-template-columns: minmax(330px, 1.2fr) minmax(280px, 1fr);
        gap: 16px;
        margin-top: 16px;
    }

    .profile-dashboard .profile-panel {
        margin: 0;
        padding: 21px;
        border-color: #2b3b49;
        background: linear-gradient(180deg, #101922, #0d151e);
    }

    .profile-dashboard .panel-eyebrow { color: #d0ae69; }
    .profile-dashboard .panel-heading h2 { color: #eff3f4; }
    .profile-about-panel { min-height: 100%; }
    .about-bio { margin: 17px 0 20px; color: #c9d1d7; line-height: 1.55; }

    .about-list { border-top: 1px solid #263746; }
    .about-row {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 14px;
        padding: 13px 0;
        border-bottom: 1px solid #263746;
        color: #8999a5;
        font-size: .8rem;
    }
    .about-row strong { color: #d9e0e4; text-align: right; overflow-wrap: anywhere; }
    .about-row .coming-soon-value { color: #c5a564; }

    .profile-dashboard-main { display: grid; gap: 16px; min-width: 0; }
    .profile-stats-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1px; overflow: hidden; border: 1px solid #2b3b49; border-radius: 12px; background: #2b3b49; }
    .profile-stat-card {
        min-width: 0;
        display: grid;
        justify-items: center;
        gap: 5px;
        padding: 20px 8px 18px;
        background: #101922;
        text-align: center;
    }
    .profile-stat-card .stat-icon { color: #10e3f2; font-size: 1.15rem; }
    .profile-stat-card strong { color: #f1f5f6; font-size: 1.25rem; }
    .profile-stat-card span:last-child { color: #8ea0ad; font-size: .74rem; }

    .badge-preview {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-top: 18px;
        padding: 15px;
        border: 1px solid #344451;
        border-radius: 11px;
        background: #111c26;
    }
    .badge-preview-icon {
        width: 52px;
        height: 52px;
        display: grid;
        place-items: center;
        flex: none;
        border: 1px solid #80652e;
        border-radius: 50%;
        color: #e4bd63;
        font-size: 1.55rem;
        box-shadow: inset 0 0 18px rgba(223,178,80,.08);
    }
    .badge-preview div { display: grid; gap: 3px; min-width: 0; }
    .badge-preview strong { color: #e6c36d; }
    .badge-preview span { color: #8899a5; font-size: .78rem; }

    .activity-placeholder {
        min-height: 180px;
        display: grid;
        place-items: center;
        align-content: center;
        gap: 12px;
        margin-top: 18px;
        padding: 24px;
        border: 1px dashed #354756;
        border-radius: 11px;
        color: #81929e;
        text-align: center;
    }
    .activity-placeholder > span { color: #10e3f2; font-size: 1.5rem; }
    .activity-placeholder p { margin: 0; max-width: 260px; line-height: 1.55; font-size: .8rem; }

    .profile-edit-form {
        display: grid;
        grid-template-columns: minmax(180px, .7fr) minmax(180px, .7fr) minmax(260px, 1.3fr);
        gap: 13px;
        align-items: start;
    }
    .edit-mode-note { grid-column: 1 / -1; margin: 0 0 2px; color: #91a1ad; font-size: .78rem; }
    .edit-field { display: grid; gap: 7px; min-width: 0; color: #cbb17a; font-size: .76rem; font-weight: 700; }
    .edit-field input,
    .edit-field textarea {
        width: 100%;
        box-sizing: border-box;
        padding: 11px 12px;
        border: 1px solid #3d5364;
        border-radius: 9px;
        background: #0b141d;
        color: #eff5f6;
        font: inherit;
        font-size: .88rem;
        font-weight: 500;
    }
    .edit-field input:focus,
    .edit-field textarea:focus { outline: 2px solid rgba(16,227,242,.38); border-color: #10e3f2; }
    .edit-field textarea { resize: vertical; min-height: 86px; }
    .edit-field small { color: #7f919e; font-size: .7rem; font-weight: 500; }
    .profile-edit-username { margin: 0; }

    .profile-edit-actions {
        grid-column: 1 / -1;
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        margin-top: 3px;
    }
    .profile-save-button,
    .profile-cancel-button {
        min-height: 42px;
        padding: 10px 18px;
        border-radius: 9px;
        font: inherit;
        font-size: .82rem;
        font-weight: 800;
        cursor: pointer;
    }
    .profile-save-button { border: 1px solid #10e3f2; background: #10e3f2; color: #031116; }
    .profile-save-button:hover { filter: brightness(1.05); }
    .profile-cancel-button { border: 1px solid #455665; background: #141e27; color: #c9d2d8; }
    .profile-save-button:disabled, .profile-cancel-button:disabled { opacity: .55; cursor: wait; }

    @media (max-width: 920px) {
        .profile-dashboard { grid-template-columns: 1fr; }
        .profile-activity-panel { grid-column: auto; }
        .profile-edit-form { grid-template-columns: 1fr 1fr; }
        .profile-edit-form .edit-field:last-of-type { grid-column: 1 / -1; }
    }

    @media (max-width: 650px) {
        .profile-page { padding: 14px 10px 35px; }
        .profile-card { padding: 10px; border-radius: 13px; }
        .profile-avatar-column { width: 88px; margin-top: -43px; }
        .profile-main-avatar { width: 86px; height: 86px; border-width: 3px; box-shadow: 0 0 0 4px #0d151e, 0 8px 20px rgba(0,0,0,.35); }
        .avatar-edit-chip { width: 30px; height: 30px; right: -2px; bottom: -2px; }
        .profile-identity-main { padding-top: 12px; }
        .profile-title-row { display: block; }
        .profile-title-row h1 { font-size: 1.45rem; }
        .public-handle-row .username-handle { font-size: .85rem; }
        .explorer-title-badge { margin-top: 9px; padding: 6px 9px; font-size: .62rem; }
        .profile-public-bio { margin-top: 11px; font-size: .82rem; }
        .profile-meta-row { gap: 8px 13px; margin-top: 11px; font-size: .7rem; }
        .profile-tabs { padding: 0 6px; }
        .profile-tab { padding: 12px 13px 10px; font-size: .72rem; }

        .profile-dashboard { grid-template-columns: 1fr; gap: 12px; margin-top: 12px; }
        .profile-activity-panel { grid-column: auto; }
        .profile-dashboard .profile-panel { padding: 17px 15px; }
        .profile-stats-grid { order: -1; }
        .profile-dashboard-main { gap: 12px; }

        .profile-edit-form { grid-template-columns: 1fr; }
        .profile-edit-form .edit-field:last-of-type { grid-column: auto; }
        .profile-edit-actions { justify-content: stretch; }
        .profile-save-button, .profile-cancel-button { flex: 1; }

        .banner-edit-soon { right: 10px; top: 10px; max-width: calc(100% - 20px); font-size: .68rem; }
    }

    @media (max-width: 390px) {
        .profile-identity-shell { grid-template-columns: 78px minmax(0, 1fr); padding-left: 11px; padding-right: 11px; }
        .profile-avatar-column { width: 74px; }
        .profile-main-avatar { width: 72px; height: 72px; }
        .profile-title-row h1 { font-size: 1.28rem; }
        .profile-stats-grid .profile-stat-card { padding-left: 4px; padding-right: 4px; }
    }

    /* ==========================================
       PROFILE POLISH — DeepMap cyan actions
       ========================================== */

    /* Ação principal nas definições */
    .settings-edit-profile {
        border-color: #10e3f2;
        background: #10e3f2;
        color: #031116;
    }
    .settings-edit-profile:hover {
        border-color: #52f0fa;
        background: #52f0fa;
        color: #031116;
    }
    .settings-edit-profile svg { color: #031116; }

    /* Botão principal de definições */
    .settings-trigger {
        border-color: rgba(16, 227, 242, .72);
        background: rgba(16, 227, 242, .10);
        color: #10e3f2;
    }
    .settings-trigger:hover,
    .profile-settings[open] > .settings-trigger {
        border-color: #10e3f2;
        background: rgba(16, 227, 242, .18);
        color: #62f1fa;
    }
    .settings-trigger:focus-visible,
    .settings-information > summary:focus-visible,
    .settings-logout:focus-visible {
        outline-color: #10e3f2;
    }

    /* Logout continua visualmente uma ação, mas sem parecer destrutivo/vermelho */
    .settings-logout {
        border-color: rgba(16, 227, 242, .48);
        background: rgba(16, 227, 242, .07);
        color: #bff9fc;
    }
    .settings-logout svg { color: #10e3f2; }
    .settings-logout:hover {
        border-color: #10e3f2;
        background: rgba(16, 227, 242, .15);
    }

    /* Ver como visitante */
    .visitor-preview-link {
        border-color: rgba(16, 227, 242, .56);
        background: rgba(16, 227, 242, .09);
        color: #9df6fb;
    }
    .visitor-preview-link:hover {
        border-color: #10e3f2;
        background: rgba(16, 227, 242, .17);
    }
    .visitor-preview-link:focus-visible {
        outline-color: #10e3f2;
    }

    /* Visibilidade: off = contorno ciano; on = preenchido ciano */
    .visibility-switch {
        border-color: rgba(16, 227, 242, .68);
        background: #17252e;
    }
    .visibility-switch.enabled {
        border-color: #10e3f2;
        background: #10e3f2;
    }
    .visibility-switch-thumb {
        background: #eafcff;
    }
    .visibility-switch.enabled .visibility-switch-thumb {
        background: #052029;
    }
    .visibility-switch:focus-visible {
        outline-color: #10e3f2;
    }
    .settings-information-body .visibility-status {
        color: #7df3fa;
    }

    /* Copiar link */
    .username-copy-button {
        border-color: rgba(16, 227, 242, .58);
        background: rgba(16, 227, 242, .08);
        color: #10e3f2;
    }
    .username-copy-button:hover {
        border-color: #10e3f2;
        background: rgba(16, 227, 242, .17);
    }
    .username-copy-button:focus-visible {
        outline-color: #10e3f2;
    }

    /* O lápis do avatar continua dourado por defeito; ciano apenas ao interagir */
    .avatar-edit-chip {
        border-color: #0d151e;
        background: #d4ab5c;
        color: #16100a;
    }
    .avatar-edit-chip:hover,
    .avatar-edit-chip:focus-visible {
        background: #10e3f2;
        color: #031116;
    }

    /* Username: uma única moldura, sem segunda borda amarela */
    .edit-field .profile-edit-username {
        border: 1px solid #3d5364;
        border-radius: 9px;
        background: #0b141d;
        color: #10e3f2;
        padding: 0 12px;
    }
    .edit-field .profile-edit-username:focus-within {
        border-color: #10e3f2;
        outline: 2px solid rgba(16, 227, 242, .30);
        outline-offset: 0;
    }
    .edit-field .profile-edit-username input {
        border: 0;
        border-radius: 0;
        background: transparent;
        padding: 11px 0;
        outline: 0;
        box-shadow: none;
    }
    .edit-field .profile-edit-username input:focus {
        border: 0;
        outline: 0;
        box-shadow: none;
    }

    /* Sem a barra de tabs, o dashboard liga diretamente ao cabeçalho. */
    .profile-showcase { border-radius: 16px; }

    /* Ajuste final: Editar perfil discreto como Terminar sessão */
    .settings-edit-profile {
        border-color: rgba(16, 227, 242, .48);
        background: rgba(16, 227, 242, .07);
        color: #bff9fc;
    }
    .settings-edit-profile:hover,
    .settings-edit-profile:focus-visible {
        border-color: #10e3f2;
        background: rgba(16, 227, 242, .15);
        color: #dffcff;
    }
    .settings-edit-profile svg {
        color: #10e3f2;
    }

    /* ==========================================
       PROFILE POLISH 2 — interação e cor
       ========================================== */

    /* O @ é identidade, não ação: dourado. */
    .edit-field .profile-edit-username > span {
        color: #d4ab5c;
        font-weight: 800;
    }

    /* Avatar + lápis reagem como uma única ação. */
    .profile-avatar-editing:hover .profile-main-avatar,
    .profile-avatar-editing:focus-within .profile-main-avatar {
        border-color: #10e3f2;
        box-shadow:
            0 0 0 6px #0d151e,
            0 0 0 9px rgba(16, 227, 242, .16),
            0 12px 30px rgba(0,0,0,.38);
    }

    .profile-avatar-editing:hover .avatar-edit-chip,
    .profile-avatar-editing:focus-within .avatar-edit-chip {
        background: #10e3f2;
        color: #031116;
    }

    /* Todos os controlos das definições têm feedback semelhante. */
    .settings-edit-profile,
    .settings-information > summary,
    .settings-logout,
    .visitor-preview-link,
    .settings-trigger {
        transition:
            background .18s ease,
            border-color .18s ease,
            color .18s ease,
            transform .18s ease;
    }

    .settings-edit-profile:hover,
    .settings-information > summary:hover,
    .settings-logout:hover,
    .visitor-preview-link:hover,
    .settings-trigger:hover {
        transform: translateY(-1px);
    }

    .settings-information > summary:hover {
        border-color: rgba(16, 227, 242, .52);
        background: rgba(16, 227, 242, .07);
    }

    /* Estado informativo = dourado. Ciano fica reservado à interação. */
    .settings-information-body .visibility-status {
        color: #d4ab5c;
    }

    /* ==========================================
       PROFILE POLISH 3 — botões consistentes
       ========================================== */

    /* Todos os controlos dentro do menu Definições usam a mesma linguagem visual. */
    .settings-edit-profile,
    .settings-information > summary,
    .settings-logout,
    .visitor-preview-link {
        border: 1px solid rgba(16, 227, 242, .58);
        background: rgba(16, 227, 242, .08);
        color: #bff9fc;
    }

    .settings-edit-profile svg,
    .settings-information > summary svg,
    .settings-logout svg,
    .visitor-preview-link svg {
        color: #10e3f2;
    }

    .settings-edit-profile:hover,
    .settings-edit-profile:focus-visible,
    .settings-information > summary:hover,
    .settings-information > summary:focus-visible,
    .settings-logout:hover,
    .settings-logout:focus-visible,
    .visitor-preview-link:hover,
    .visitor-preview-link:focus-visible {
        border-color: #10e3f2;
        background: rgba(16, 227, 242, .15);
        color: #e3fdff;
        transform: translateY(-1px);
    }

    .settings-information > summary .settings-chevron {
        color: #8eeff6;
    }

    /* Guardar alterações continua a ser a única ação sólida em ciano. */
    .profile-save-button {
        border-color: #10e3f2;
        background: #10e3f2;
        color: #031116;
    }

    /* ==========================================
       PROFILE COLOR RESET — DeepMap original gold
       Mantém o novo layout, reverte apenas a paleta
       ========================================== */

    .settings-trigger,
    .settings-edit-profile,
    .settings-information > summary,
    .settings-logout,
    .visitor-preview-link,
    .username-copy-button {
        border-color: rgba(200, 163, 85, .48);
        background: rgba(200, 163, 85, .07);
        color: #d9bd84;
    }

    .settings-trigger:hover,
    .profile-settings[open] > .settings-trigger,
    .settings-edit-profile:hover,
    .settings-edit-profile:focus-visible,
    .settings-information > summary:hover,
    .settings-information > summary:focus-visible,
    .settings-logout:hover,
    .settings-logout:focus-visible,
    .visitor-preview-link:hover,
    .visitor-preview-link:focus-visible,
    .username-copy-button:hover,
    .username-copy-button:focus-visible {
        border-color: #c8a355;
        background: rgba(200, 163, 85, .15);
        color: #f0d99f;
    }

    .settings-trigger:focus-visible,
    .settings-information > summary:focus-visible,
    .settings-logout:focus-visible,
    .visitor-preview-link:focus-visible,
    .username-copy-button:focus-visible {
        outline-color: rgba(200, 163, 85, .35);
    }

    .settings-trigger svg,
    .settings-edit-profile svg,
    .settings-information > summary svg,
    .settings-logout svg,
    .visitor-preview-link svg,
    .username-copy-button svg,
    .settings-information > summary .settings-chevron {
        color: #c8a355;
    }

    .visibility-switch {
        border-color: #66616a;
        background: #4a4851;
    }

    .visibility-switch.enabled {
        border-color: #c8a355;
        background: #92733e;
    }

    .visibility-switch-thumb {
        background: #f3efe7;
    }

    .visibility-switch.enabled .visibility-switch-thumb {
        background: #f3efe7;
    }

    .visibility-switch:focus-visible {
        outline-color: #c8a355;
    }

    .settings-information-body .visibility-status {
        color: #d7b573;
    }

    .avatar-edit-chip {
        border-color: #0d151e;
        background: #d4ab5c;
        color: #16100a;
    }

    .avatar-edit-chip:hover,
    .avatar-edit-chip:focus-visible,
    .profile-avatar-editing:hover .avatar-edit-chip,
    .profile-avatar-editing:focus-within .avatar-edit-chip {
        background: #eed18a;
        color: #16100a;
    }

    .profile-avatar-editing:hover .profile-main-avatar,
    .profile-avatar-editing:focus-within .profile-main-avatar,
    .profile-main-avatar.avatar-editable:hover {
        border-color: #d4ab5c;
        box-shadow:
            0 0 0 6px #0d151e,
            0 0 0 9px rgba(200, 163, 85, .14),
            0 12px 30px rgba(0,0,0,.38);
    }

    .edit-field .profile-edit-username {
        border-color: #3d5364;
        color: #d4ab5c;
    }

    .edit-field .profile-edit-username:focus-within,
    .edit-field input:focus,
    .edit-field textarea:focus {
        border-color: #c8a355;
        outline-color: rgba(200, 163, 85, .30);
    }

    .edit-field .profile-edit-username > span {
        color: #d4ab5c;
    }

    .profile-save-button {
        border-color: #c8a355;
        background: #c8a355;
        color: #171717;
    }

    .profile-save-button:hover {
        background: #d9b76c;
        border-color: #d9b76c;
    }

    .profile-stat-card .stat-icon,
    .activity-placeholder > span {
        color: #c8a355;
    }

    .profile-tab.active {
        border-color: #c8a355;
    }

    .username-change-warning {
        display: block;
        margin-top: 4px;
        color: #d6bd88;
        font-size: .76rem;
        line-height: 1.45;
    }


    /* Global header cleanup: settings now belongs to the profile identity area. */
    .profile-showcase { overflow: visible; }
    .profile-banner { overflow: hidden; border-radius: 15px 15px 0 0; }
    .profile-title-actions .profile-toolbar { position: relative; z-index: 35; margin: 0; }
    .profile-title-actions .profile-settings { position: relative; }
    .profile-title-actions .settings-menu { right: 0; left: auto; z-index: 60; }

    @media (max-width: 650px) {
        .profile-title-actions {
            margin: 9px 0 0;
            justify-content: flex-start;
            flex-wrap: wrap;
        }
        .profile-title-actions .explorer-title-badge { margin-top: 0; }
    }


    /* ==========================================
       PROFILE MOBILE — layout only
       Mantém a lógica e o desktop intactos.
       ========================================== */
    @media (max-width: 650px) {
        .profile-identity-shell {
            grid-template-columns: minmax(0, 1fr);
            gap: 0;
            min-height: 0;
            padding: 0 14px 22px;
        }

        .profile-avatar-column {
            width: 92px;
            margin: -46px auto 0;
            justify-self: center;
        }

        .profile-main-avatar {
            width: 90px;
            height: 90px;
        }

        .profile-identity-main {
            width: 100%;
            padding-top: 14px;
            text-align: center;
        }

        .profile-title-row {
            display: block;
            width: 100%;
        }

        .profile-title-row h1 {
            font-size: 1.55rem;
            line-height: 1.15;
            overflow-wrap: anywhere;
        }

        .public-handle-row {
            justify-content: center;
            flex-wrap: wrap;
        }

        .profile-title-actions {
            position: relative;
            justify-content: center;
            flex-wrap: wrap;
            width: 100%;
            margin: 12px 0 0;
        }

        .profile-title-actions .profile-toolbar,
        .profile-title-actions .profile-settings {
            position: static;
        }

        .profile-title-actions .settings-menu {
            right: auto;
            left: 50%;
            width: min(320px, calc(100vw - 40px));
            max-width: calc(100vw - 40px);
            transform: translateX(-50%);
        }

        .explorer-title-badge {
            margin-top: 0;
        }

        .profile-public-bio {
            max-width: 34rem;
            margin: 13px auto 0;
            text-align: center;
        }

        .profile-meta-row {
            justify-content: center;
        }

        .profile-edit-form {
            width: 100%;
            text-align: left;
        }

        .edit-mode-note {
            text-align: center;
        }
    }

    @media (max-width: 420px) {
        .profile-page {
            padding-left: 8px;
            padding-right: 8px;
        }

        .profile-card {
            padding: 8px;
        }

        .profile-identity-shell {
            padding-left: 10px;
            padding-right: 10px;
        }

        .profile-title-row h1 {
            font-size: 1.42rem;
        }

        .profile-edit-actions {
            flex-direction: column;
        }

        .profile-save-button,
        .profile-cancel-button {
            width: 100%;
        }
    }

</style>
