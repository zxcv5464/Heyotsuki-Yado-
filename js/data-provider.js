(() => {
  const client = window.SUPABASE_CLIENT;
  const siteSettingKeys = [
    "bookingUrl",
    "discordUrl",
    "threadsUrl",
    "address",
    "openingDays",
    "openingHours",
    "status",
  ];

  const hasRows = (data) => Array.isArray(data) && data.length > 0;

  const localStaff = () => window.STAFF_DATA || [];
  const localMenu = () => window.MENU_DATA || null;
  const localMenus = () => window.SITE_CONFIG?.menus || [];
  const parseJson = (value, fallback) => {
    try {
      return JSON.parse(value);
    } catch {
      return fallback;
    }
  };

  const getSiteConfig = async () => {
    const fallback = window.SITE_CONFIG || {};
    if (!client) return fallback;

    try {
      const { data, error } = await client
        .from("site_settings")
        .select("key, value")
        .in("key", siteSettingKeys);

      if (error || !hasRows(data)) return fallback;

      const settings = Object.fromEntries(
        data.map((setting) => [setting.key, setting.value])
      );
      return {
        ...fallback,
        ...settings,
      };
    } catch (error) {
      console.warn("Supabase site settings read failed; using local config.", error);
      return fallback;
    }
  };

  const getStaff = async () => {
    if (!client) return localStaff();

    try {
      const { data, error } = await client
        .from("staff_members")
        .select("name, subtitle, quote, role, image_url, sort_order")
        .eq("is_visible", true)
        .order("sort_order", { ascending: true });

      if (error || !hasRows(data)) return localStaff();

      return data.map((member, index) => ({
        name: member.name,
        subtitle: member.subtitle,
        quote: member.quote,
        role: member.role,
        image: member.image_url,
        stagger: (index % 4) + 1,
      }));
    } catch (error) {
      console.warn("Supabase staff read failed; using local data.", error);
      return localStaff();
    }
  };

  const getMenus = async () => {
    const fallback = localMenus();
    if (!client) return fallback;

    try {
      const { data, error } = await client
        .from("menus")
        .select(
          "key, title, short_title, english_title, description, href, theme, sort_order"
        )
        .eq("is_visible", true)
        .order("sort_order", { ascending: true });

      if (error || !hasRows(data)) return fallback;

      return data.map((menu) => ({
        key: menu.key,
        title: menu.title,
        shortTitle: menu.short_title,
        englishTitle: menu.english_title,
        description: menu.description,
        href: menu.href,
        theme: menu.theme,
        sortOrder: menu.sort_order,
      }));
    } catch (error) {
      console.warn("Supabase menus read failed; using local config.", error);
      return fallback;
    }
  };

  const getMenu = async (menuKey) => {
    const fallback = localMenu();
    if (!client) return fallback;

    try {
      const settingKeys = [
        `menu.${menuKey}.pageTitle`,
        `menu.${menuKey}.subtitle`,
        `menu.${menuKey}.footer`,
      ];
      const [menuResult, sectionsResult, settingsResult] = await Promise.all([
        client
          .from("menus")
          .select(
            "key, title, short_title, english_title, description, href, theme"
          )
          .eq("key", menuKey)
          .eq("is_visible", true)
          .maybeSingle(),
        client
          .from("menu_sections")
          .select(
            "id, title, subtitle, notice, layout_type, sort_order"
          )
          .eq("menu_key", menuKey)
          .eq("is_visible", true)
          .order("sort_order", { ascending: true }),
        client
          .from("site_settings")
          .select("key, value")
          .in("key", settingKeys),
      ]);

      if (
        menuResult.error ||
        sectionsResult.error ||
        settingsResult.error
      ) {
        return fallback;
      }

      if (!menuResult.data) return null;

      const sectionIds = sectionsResult.data.map((section) => section.id);
      let itemRows = [];
      if (sectionIds.length) {
        const { data, error: itemsError } = await client
          .from("menu_items")
          .select(
            "section_id, name, description, price, featured, sort_order"
          )
          .in("section_id", sectionIds)
          .eq("is_visible", true)
          .order("sort_order", { ascending: true });

        if (itemsError) return fallback;
        itemRows = data || [];
      }

      const itemsBySection = itemRows.reduce((groups, item) => {
        (groups[item.section_id] ||= []).push(item);
        return groups;
      }, {});

      const sections = [];
      const settings = Object.fromEntries(
        (settingsResult.data || []).map((setting) => [
          setting.key,
          setting.value,
        ])
      );
      (sectionsResult.data || []).forEach((section) => {
        const normalized = {
          title: section.title,
          label: section.subtitle,
          notice: section.notice,
          layout: section.layout_type.replace("nested_", ""),
          items: (itemsBySection[section.id] || []).map((item) => ({
            name: item.name,
            description: item.description,
            price: item.price,
            featured: item.featured,
          })),
        };

        if (section.layout_type.startsWith("nested_") && sections.length) {
          (sections.at(-1).nestedSections ||= []).push(normalized);
        } else {
          sections.push(normalized);
        }
      });

      return {
        title:
          settings[`menu.${menuKey}.pageTitle`] || menuResult.data.title,
        subtitle:
          settings[`menu.${menuKey}.subtitle`] ||
          menuResult.data.english_title,
        sections,
        footer: parseJson(
          settings[`menu.${menuKey}.footer`],
          fallback?.footer || []
        ),
      };
    } catch (error) {
      console.warn(`Supabase menu read failed for ${menuKey}; using local data.`, error);
      return fallback;
    }
  };

  window.DATA_PROVIDER = {
    getSiteConfig,
    getStaff,
    getMenus,
    getMenu,
  };
})();
