#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ===================================================================
// 结构体定义
// ===================================================================
struct SBHIconGridSize {
    unsigned short columns;
    unsigned short rows;
};

struct SBHIconGridRange {
    unsigned long long location;
    struct SBHIconGridSize size;
};

// ===================================================================
// 接口声明（完整声明，避免 forward declaration 错误）
// ===================================================================
@interface SBIcon : NSObject
- (NSString *)leafIdentifier;
- (NSString *)applicationBundleIdentifier;
- (NSString *)nodeIdentifier;
- (id)folder;
@end

@interface SBFolder : NSObject
- (NSString *)uniqueIdentifier;
@end

@interface SBIconListView : UIView
- (NSString *)iconLocation;
- (BOOL)allowsGaps;
- (id)model;
- (void)layoutIconsNow;
- (void)setIconsNeedLayout;
- (void)layoutIconsIfNeeded;
@end

@interface SBIconListModel : NSObject
- (NSString *)uniqueIdentifier;
- (unsigned long long)maxNumberOfIcons;
- (NSArray *)icons;
- (id)iconAtIndex:(unsigned long long)index;
- (unsigned long long)indexForIcon:(id)icon;
- (unsigned long long)gridCellIndexForIcon:(id)icon gridCellInfoOptions:(unsigned long long)options;
- (BOOL)allowsFixedIconLocations;
- (long long)fixedIconLocationBehavior;
- (BOOL)isIconFixed:(id)icon;
- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options;
- (unsigned long long)fixedLocationForIcon:(id)icon;
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon;
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon options:(unsigned long long)options;
- (void)saveCurrentIconLocationsAsFixed;
- (void)saveOnlyRequiredIconLocationsAsFixed;
- (void)saveOnlyRequiredIconLocationsAsFixedIfRequired;
- (void)removeAllFixedIconLocations;
- (void)removeFixedIconLocationForIcon:(id)icon;
- (void)removeFixedIconLocationsForIcons:(id)icons;
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfo:(id)info;
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfoOptions:(unsigned long long)options;
- (id)_updateModelByRepairingGapsIfNecessary;
- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons;
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoiding;
- (BOOL)isGridLayoutValid;
- (BOOL)isGridLayoutValid:(id)info;
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options;
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)outIcons;
- (BOOL)canUseFastGridLayoutValidity;
- (BOOL)requiresSomeFixedIconLocations;
- (void)setIcons:(NSArray *)icons;
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options;
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (id)setIconsFromIconListModel:(id)model;
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index;
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options;
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info;
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options;
- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options;
- (void)removeIcon:(id)icon;
- (void)removeIcon:(id)icon options:(unsigned long long)options;
- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (void)removeIconAtIndex:(unsigned long long)index;
- (void)removeIconAtIndex:(unsigned long long)index options:(unsigned long long)options;
@end

@interface SBHIconManager : NSObject
- (long long)listsFixedIconLocationBehavior;
- (long long)listsFixedIconLocationBehaviorForFolderClass:(Class)cls;
- (long long)iconModel:(id)model listsFixedIconLocationBehaviorForFolderClass:(Class)cls;
- (void)ensureFixedIconLocationsIfNecessary;
@end

// 完整声明 SBIconView，解决 forward declaration + [self icon] 错误
@interface SBIconView : UIView
- (id)icon;
@end

// ===================================================================
// 坐标管理引擎（崩溃安全版）
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.iosdump.freegrid.plist"

static NSMutableDictionary *gGridConfig = nil;
static dispatch_queue_t gSaveQueue = nil;
static NSLock *gConfigLock = nil;
static BOOL gInfrastructureReady = NO;

// 拖拽/mutation 期间保守处理
static BOOL gIsDuringMutation = NO;
static NSHashTable *gCurrentlyDraggedIcons = nil; // 弱引用当前正在拖的图标

static void EnsureInfrastructure(void) {
    if (gInfrastructureReady) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSaveQueue = dispatch_queue_create("com.iosdump.freegrid.save", DISPATCH_QUEUE_SERIAL);
        gConfigLock = [[NSLock alloc] init];
        gCurrentlyDraggedIcons = [NSHashTable weakObjectsHashTable];
        gInfrastructureReady = YES;
    });
}

static void LoadGridConfig(void) {
    EnsureInfrastructure();
    if (gGridConfig) return;

    [gConfigLock lock];
    if (gGridConfig) {
        [gConfigLock unlock];
        return;
    }
    @try {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        gGridConfig = dict ? [dict mutableCopy] : [NSMutableDictionary dictionary];
    } @catch (__unused NSException *e) {
        gGridConfig = [NSMutableDictionary dictionary];
    }
    if (!gGridConfig) gGridConfig = [NSMutableDictionary dictionary];
    [gConfigLock unlock];
}

static void SaveGridConfig(void) {
    EnsureInfrastructure();
    if (!gGridConfig) return;

    NSDictionary *snapshot = nil;
    [gConfigLock lock];
    snapshot = [gGridConfig copy];
    [gConfigLock unlock];
    if (!snapshot) return;

    dispatch_async(gSaveQueue, ^{
        @try {
            [snapshot writeToFile:PLIST_PATH atomically:YES];
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @0666}
                                             ofItemAtPath:PLIST_PATH
                                                    error:nil];
        } @catch (__unused NSException *e) {}
    });
}

static NSString *GetIconID(id icon) {
    if (!icon) return nil;
    @try {
        Class widgetClass = NSClassFromString(@"SBWidgetIcon");
        if (widgetClass && [icon isKindOfClass:widgetClass]) {
            if ([icon respondsToSelector:@selector(leafIdentifier)]) {
                NSString *leaf = [icon leafIdentifier];
                if ([leaf isKindOfClass:[NSString class]] && leaf.length > 0)
                    return [@"widget:" stringByAppendingString:leaf];
            }
            if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
                NSString *node = [icon nodeIdentifier];
                if ([node isKindOfClass:[NSString class]] && node.length > 0)
                    return [@"widget-node:" stringByAppendingString:node];
            }
            return [NSString stringWithFormat:@"widget-%p", icon];
        }

        Class folderIconClass = NSClassFromString(@"SBFolderIcon");
        if (folderIconClass && [icon isKindOfClass:folderIconClass]) {
            if ([icon respondsToSelector:@selector(folder)]) {
                id folder = [icon folder];
                if (folder && [folder respondsToSelector:@selector(uniqueIdentifier)]) {
                    NSString *fid = [folder uniqueIdentifier];
                    if ([fid isKindOfClass:[NSString class]] && fid.length > 0)
                        return [@"folder:" stringByAppendingString:fid];
                }
            }
            if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
                NSString *node = [icon nodeIdentifier];
                if ([node isKindOfClass:[NSString class]] && node.length > 0)
                    return [@"folder-node:" stringByAppendingString:node];
            }
            if ([icon respondsToSelector:@selector(leafIdentifier)]) {
                NSString *leaf = [icon leafIdentifier];
                if ([leaf isKindOfClass:[NSString class]] && leaf.length > 0)
                    return [@"folder-leaf:" stringByAppendingString:leaf];
            }
            return [NSString stringWithFormat:@"folder-%p", icon];
        }
        if ([icon respondsToSelector:@selector(leafIdentifier)]) {
            NSString *leaf = [icon leafIdentifier];
            if ([leaf isKindOfClass:[NSString class]] && leaf.length > 0) return leaf;
        }
        if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
            NSString *bid = [icon applicationBundleIdentifier];
            if ([bid isKindOfClass:[NSString class]] && bid.length > 0) return bid;
        }
        if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
            NSString *node = [icon nodeIdentifier];
            if ([node isKindOfClass:[NSString class]] && node.length > 0) return node;
        }
    } @catch (__unused NSException *e) {}
    return [NSString stringWithFormat:@"%p", icon];
}

static BOOL IsDockList(SBIconListModel *model) {
    return NO;
}

static BOOL IsPlaceholderIcon(id icon) {
    if (!icon) return NO;
    @try {
        Class phClass = NSClassFromString(@"SBPlaceholderIcon");
        if (phClass && [icon isKindOfClass:phClass]) return YES;

        // 安全调用 isPlaceholder（避免编译器报“no known instance method”）
        if ([icon respondsToSelector:@selector(isPlaceholder)]) {
            BOOL (*msgSend)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
            if (msgSend(icon, @selector(isPlaceholder))) return YES;
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

static void SafeSetFixedLocation(SBIconListModel *model, id icon, unsigned long long loc) {
    if (!model || !icon || IsPlaceholderIcon(icon)) return;
    @try {
        if ([model respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
            [model setFixedLocation:loc forIcon:icon options:0];
        } else if ([model respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
            [model setFixedLocation:loc forIcon:icon];
        }
    } @catch (__unused NSException *e) {}
}

// 只清理配置，绝不在敏感路径主动重新分配位置
static void ForceRemoveFixedFromConfig(SBIconListModel *model, id icon) {
    if (!model || !icon || IsPlaceholderIcon(icon)) return;
    @try {
        NSString *listID = nil;
        if ([model respondsToSelector:@selector(uniqueIdentifier)]) {
            listID = [model uniqueIdentifier];
        }
        NSString *iconID = GetIconID(icon);
        if (![listID isKindOfClass:[NSString class]] || !iconID) return;

        LoadGridConfig();
        [gConfigLock lock];
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
        if (listConfig && listConfig[iconID]) {
            [listConfig removeObjectForKey:iconID];
            if (listConfig.count == 0) {
                [gGridConfig removeObjectForKey:listID];
            } else {
                gGridConfig[listID] = listConfig;
            }
            [gConfigLock unlock];
            SaveGridConfig();
        } else {
            [gConfigLock unlock];
        }
    } @catch (__unused NSException *e) {}
}

// 核心 Apply（拖拽期间完全跳过）
static void ApplyUserMovedLocations(SBIconListModel *model) {
    if (!model || IsDockList(model) || gIsDuringMutation) return;

    @try {
        NSString *listID = nil;
        if ([model respondsToSelector:@selector(uniqueIdentifier)]) {
            listID = [model uniqueIdentifier];
        }
        if (![listID isKindOfClass:[NSString class]] || listID.length == 0) return;

        LoadGridConfig();

        BOOL needBootstrap = NO;
        [gConfigLock lock];
        NSDictionary *existing = gGridConfig[listID];
        needBootstrap = (existing == nil || existing.count == 0);
        [gConfigLock unlock];

        NSArray *icons = nil;
        if ([model respondsToSelector:@selector(icons)]) {
            icons = [model icons];
        }
        if (![icons isKindOfClass:[NSArray class]] || icons.count == 0) return;

        unsigned long long max = 0;
        if ([model respondsToSelector:@selector(maxNumberOfIcons)]) {
            max = [model maxNumberOfIcons];
        }
        if (max == 0) return;

        if (needBootstrap) {
            NSMutableDictionary *newConfig = [NSMutableDictionary dictionaryWithCapacity:icons.count];
            for (NSUInteger i = 0; i < icons.count; i++) {
                id icon = icons[i];
                if (!icon || IsPlaceholderIcon(icon)) continue;
                NSString *iconID = GetIconID(icon);
                if (!iconID) continue;

                unsigned long long loc = i;
                @try {
                    if ([model respondsToSelector:@selector(gridCellIndexForIcon:gridCellInfoOptions:)]) {
                        unsigned long long gridLoc = [model gridCellIndexForIcon:icon gridCellInfoOptions:0];
                        if (gridLoc != NSNotFound && gridLoc < max) loc = gridLoc;
                    }
                } @catch (__unused NSException *e) {}

                if (loc < max) {
                    newConfig[iconID] = @(loc);
                    SafeSetFixedLocation(model, icon, loc);
                }
            }
            if (newConfig.count > 0) {
                [gConfigLock lock];
                gGridConfig[listID] = newConfig;
                [gConfigLock unlock];
                SaveGridConfig();
            }
            return;
        }

        NSDictionary *listConfig = nil;
        [gConfigLock lock];
        listConfig = [gGridConfig[listID] copy];
        [gConfigLock unlock];
        if (!listConfig.count) return;

        for (id icon in icons) {
            if (!icon || IsPlaceholderIcon(icon)) continue;
            // 正在被拖的图标暂时不强制 fixed
            if ([gCurrentlyDraggedIcons containsObject:icon]) continue;

            NSString *iconID = GetIconID(icon);
            if (!iconID) continue;
            NSNumber *num = listConfig[iconID];
            if (![num isKindOfClass:[NSNumber class]]) continue;
            unsigned long long loc = [num unsignedLongLongValue];
            if (loc >= max) continue;
            SafeSetFixedLocation(model, icon, loc);
        }
    } @catch (__unused NSException *e) {}
}

static void CleanupIconFromPlist(SBIconListModel *model, id icon) {
    if (!model || !icon) return;
    @try {
        NSString *listID = nil;
        if ([model respondsToSelector:@selector(uniqueIdentifier)]) {
            listID = [model uniqueIdentifier];
        }
        NSString *iconID = GetIconID(icon);
        if (![listID isKindOfClass:[NSString class]] || !iconID) return;

        LoadGridConfig();
        [gConfigLock lock];
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
        if (listConfig && listConfig[iconID]) {
            [listConfig removeObjectForKey:iconID];
            if (listConfig.count == 0) {
                [gGridConfig removeObjectForKey:listID];
            } else {
                gGridConfig[listID] = listConfig;
            }
            [gConfigLock unlock];
            SaveGridConfig();
        } else {
            [gConfigLock unlock];
        }
    } @catch (__unused NSException *e) {}
}

static void RecordUserMovedIcon(SBIconListModel *model, id icon, unsigned long long index) {
    if (!model || !icon || IsPlaceholderIcon(icon)) return;
    @try {
        if (index == NSNotFound || IsDockList(model)) return;
        unsigned long long max = 0;
        if ([model respondsToSelector:@selector(maxNumberOfIcons)]) {
            max = [model maxNumberOfIcons];
        }
        if (index >= max) return;

        NSString *listID = nil;
        if ([model respondsToSelector:@selector(uniqueIdentifier)]) {
            listID = [model uniqueIdentifier];
        }
        NSString *iconID = GetIconID(icon);
        if (![listID isKindOfClass:[NSString class]] || listID.length == 0 || !iconID) return;

        SafeSetFixedLocation(model, icon, index);

        LoadGridConfig();
        [gConfigLock lock];
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
        if (!listConfig) listConfig = [NSMutableDictionary dictionary];
        listConfig[iconID] = @(index);
        gGridConfig[listID] = listConfig;
        [gConfigLock unlock];
        SaveGridConfig();

        ApplyUserMovedLocations(model);
    } @catch (__unused NSException *e) {}
}

// ===================================================================
// 视图层
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    @try {
        if ([self respondsToSelector:@selector(iconLocation)]) {
            NSString *location = [self iconLocation];
            if ([location isKindOfClass:[NSString class]] &&
                ([location containsString:@"Dock"] || [location containsString:@"dock"])) {
                return %orig;
            }
        }
        return YES;
    } @catch (__unused NSException *e) {
        return %orig;
    }
}

- (void)layoutIconsNow {
    @try {
        if ([self respondsToSelector:@selector(model)]) {
            id model = [self model];
            if (model) ApplyUserMovedLocations(model);
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

- (void)setIconsNeedLayout {
    @try {
        if ([self respondsToSelector:@selector(model)]) {
            id model = [self model];
            if (model) ApplyUserMovedLocations(model);
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

- (void)layoutIconsIfNeeded {
    @try {
        if ([self respondsToSelector:@selector(model)]) {
            id model = [self model];
            if (model) ApplyUserMovedLocations(model);
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

%end

// ===================================================================
// Manager 层
// ===================================================================
%hook SBHIconManager

- (long long)listsFixedIconLocationBehavior {
    return 1;
}

- (long long)listsFixedIconLocationBehaviorForFolderClass:(Class)cls {
    return 1;
}

- (long long)iconModel:(id)model listsFixedIconLocationBehaviorForFolderClass:(Class)cls {
    return 1;
}

- (void)ensureFixedIconLocationsIfNecessary {
}

%end

// ===================================================================
// 数据层
// ===================================================================
%hook SBIconListModel

- (BOOL)allowsFixedIconLocations {
    return YES;
}

- (long long)fixedIconLocationBehavior {
    return 1;
}

- (BOOL)requiresSomeFixedIconLocations {
    return YES;
}

- (BOOL)isIconFixed:(id)icon {
    if (!icon || IsDockList(self) || IsPlaceholderIcon(icon)) return %orig;
    if ([gCurrentlyDraggedIcons containsObject:icon]) return NO;

    @try {
        NSString *listID = nil;
        if ([self respondsToSelector:@selector(uniqueIdentifier)]) {
            listID = [self uniqueIdentifier];
        }
        NSString *iconID = GetIconID(icon);
        if (![listID isKindOfClass:[NSString class]] || !iconID) return %orig;

        LoadGridConfig();
        BOOL fixed = NO;
        [gConfigLock lock];
        NSDictionary *cfg = gGridConfig[listID];
        if (cfg && cfg[iconID]) fixed = YES;
        [gConfigLock unlock];
        if (fixed) return YES;
    } @catch (__unused NSException *e) {}
    return %orig;
}

- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options {
    return [self isIconFixed:icon];
}

- (unsigned long long)fixedLocationForIcon:(id)icon {
    if (!icon || IsDockList(self) || IsPlaceholderIcon(icon)) return %orig;
    if ([gCurrentlyDraggedIcons containsObject:icon]) return %orig;

    @try {
        NSString *listID = nil;
        if ([self respondsToSelector:@selector(uniqueIdentifier)]) {
            listID = [self uniqueIdentifier];
        }
        NSString *iconID = GetIconID(icon);
        if (![listID isKindOfClass:[NSString class]] || !iconID) return %orig;

        LoadGridConfig();
        NSNumber *num = nil;
        [gConfigLock lock];
        NSDictionary *cfg = gGridConfig[listID];
        if (cfg) num = cfg[iconID];
        [gConfigLock unlock];

        if ([num isKindOfClass:[NSNumber class]]) {
            unsigned long long loc = [num unsignedLongLongValue];
            unsigned long long max = 0;
            if ([self respondsToSelector:@selector(maxNumberOfIcons)]) {
                max = [self maxNumberOfIcons];
            }
            if (loc < max) {
                SafeSetFixedLocation(self, icon, loc);
                return loc;
            }
        }
    } @catch (__unused NSException *e) {}
    return %orig;
}

- (unsigned long long)gridCellIndexForIcon:(id)icon gridCellInfoOptions:(unsigned long long)options {
    if (!icon || IsDockList(self) || IsPlaceholderIcon(icon)) return %orig;
    if ([gCurrentlyDraggedIcons containsObject:icon]) return %orig;

    @try {
        NSString *listID = nil;
        if ([self respondsToSelector:@selector(uniqueIdentifier)]) {
            listID = [self uniqueIdentifier];
        }
        NSString *iconID = GetIconID(icon);
        if (![listID isKindOfClass:[NSString class]] || !iconID) return %orig;

        LoadGridConfig();
        NSNumber *num = nil;
        [gConfigLock lock];
        NSDictionary *cfg = gGridConfig[listID];
        if (cfg) num = cfg[iconID];
        [gConfigLock unlock];

        if ([num isKindOfClass:[NSNumber class]]) {
            unsigned long long loc = [num unsignedLongLongValue];
            unsigned long long max = 0;
            if ([self respondsToSelector:@selector(maxNumberOfIcons)]) {
                max = [self maxNumberOfIcons];
            }
            if (loc < max) return loc;
        }
    } @catch (__unused NSException *e) {}
    return %orig;
}

- (void)removeAllFixedIconLocations {}
- (void)removeFixedIconLocationForIcon:(id)icon {
    if (icon && !IsPlaceholderIcon(icon)) {
        ForceRemoveFixedFromConfig(self, icon);
    }
}
- (void)removeFixedIconLocationsForIcons:(id)icons {
    if ([icons isKindOfClass:[NSArray class]]) {
        for (id icon in icons) {
            if (!IsPlaceholderIcon(icon)) ForceRemoveFixedFromConfig(self, icon);
        }
    }
}
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfo:(id)info {}
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfoOptions:(unsigned long long)options {}

- (id)_updateModelByRepairingGapsIfNecessary { return nil; }
- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons { return nil; }
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoiding { return icons; }

- (BOOL)isGridLayoutValid { return YES; }
- (BOOL)isGridLayoutValid:(id)info { return YES; }
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options { return YES; }
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)outIcons {
    if (outIcons) *outIcons = nil;
    return YES;
}
- (BOOL)canUseFastGridLayoutValidity { return NO; }

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index {
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
        if (index < max) return index;
    }
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
        if (index < max) return index;
    }
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info {
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
        if (index < max) return index;
    }
    return %orig;
}

- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    gIsDuringMutation = YES;
    id result = %orig;
    @try {
        if (icon && !IsPlaceholderIcon(icon)) {
            RecordUserMovedIcon(self, icon, index);
        }
    } @catch (__unused NSException *e) {}
    gIsDuringMutation = NO;
    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    gIsDuringMutation = YES;
    id result = %orig;
    @try {
        if (icon && !IsPlaceholderIcon(icon)) {
            RecordUserMovedIcon(self, icon, index);
        }
    } @catch (__unused NSException *e) {}
    gIsDuringMutation = NO;
    return result;
}

- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options {
    gIsDuringMutation = YES;
    id result = %orig;
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}
    gIsDuringMutation = NO;
    return result;
}

- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options {
    gIsDuringMutation = YES;
    %orig;
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}
    gIsDuringMutation = NO;
}

- (void)removeIcon:(id)icon {
    %orig;
    @try { CleanupIconFromPlist(self, icon); } @catch (__unused NSException *e) {}
}
- (void)removeIcon:(id)icon options:(unsigned long long)options {
    %orig;
    @try { CleanupIconFromPlist(self, icon); } @catch (__unused NSException *e) {}
}
- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    %orig;
    @try { CleanupIconFromPlist(self, icon); } @catch (__unused NSException *e) {}
}
- (void)removeIconAtIndex:(unsigned long long)index {
    id icon = nil;
    @try {
        NSArray *icons = [self icons];
        if ([icons isKindOfClass:[NSArray class]] && index < icons.count) icon = icons[index];
    } @catch (__unused NSException *e) {}
    %orig;
    if (icon) { @try { CleanupIconFromPlist(self, icon); } @catch (__unused NSException *e) {} }
}
- (void)removeIconAtIndex:(unsigned long long)index options:(unsigned long long)options {
    id icon = nil;
    @try {
        NSArray *icons = [self icons];
        if ([icons isKindOfClass:[NSArray class]] && index < icons.count) icon = icons[index];
    } @catch (__unused NSException *e) {}
    %orig;
    if (icon) { @try { CleanupIconFromPlist(self, icon); } @catch (__unused NSException *e) {} }
}

- (void)setIcons:(NSArray *)icons {
    %orig;
    @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options {
    id result = %orig;
    @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    return result;
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    return result;
}
- (id)setIconsFromIconListModel:(id)model {
    id result = %orig;
    @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    return result;
}

%end

// ===================================================================
// 跟踪当前正在拖拽的图标（关键！防止 lift 阶段崩溃）
// ===================================================================
%hook SBIconView

- (void)dragInteraction:(id)interaction sessionWillBegin:(id)session {
    @try {
        id icon = [self icon];
        if (icon) {
            EnsureInfrastructure();
            [gCurrentlyDraggedIcons addObject:icon];
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

- (void)dragInteraction:(id)interaction session:(id)session willEndWithOperation:(unsigned long long)operation {
    @try {
        id icon = [self icon];
        if (icon) {
            [gCurrentlyDraggedIcons removeObject:icon];
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

- (void)dragInteraction:(id)interaction sessionDidEnd:(id)session {
    @try {
        id icon = [self icon];
        if (icon) {
            [gCurrentlyDraggedIcons removeObject:icon];
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

%end
