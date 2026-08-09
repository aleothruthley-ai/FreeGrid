#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

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
// 接口声明
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

// ===================================================================
// 坐标管理引擎（内存优先、低开销、防崩溃）
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.iosdump.freegrid.plist"

static NSMutableDictionary *gGridConfig = nil;   // 全程内存缓存，热路径零磁盘
static dispatch_queue_t gSaveQueue = nil;
static NSLock *gConfigLock = nil;
static BOOL gInfrastructureReady = NO;

static void EnsureInfrastructure(void) {
    if (gInfrastructureReady) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSaveQueue = dispatch_queue_create("com.iosdump.freegrid.save", DISPATCH_QUEUE_SERIAL);
        gConfigLock = [[NSLock alloc] init];
        gInfrastructureReady = YES;
    });
}

// 只在第一次调用时读磁盘，之后全部走内存
static void LoadGridConfig(void) {
    EnsureInfrastructure();
    if (gGridConfig) return;          // 已在内存，直接返回（最快路径）

    [gConfigLock lock];
    if (gGridConfig) {                // 双重检查
        [gConfigLock unlock];
        return;
    }
    @try {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        gGridConfig = dict ? [dict mutableCopy] : [NSMutableDictionary dictionary];
    } @catch (__unused NSException *e) {
        gGridConfig = [NSMutableDictionary dictionary];
    }
    if (!gGridConfig) {
        gGridConfig = [NSMutableDictionary dictionary];
    }
    [gConfigLock unlock];
}

// 异步写盘，不阻塞主线程
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

// 轻量、无异常的 Icon ID 获取
static NSString *GetIconID(id icon) {
    if (!icon) return nil;

    @try {
        Class folderIconClass = NSClassFromString(@"SBFolderIcon");
        if (folderIconClass && [icon isKindOfClass:folderIconClass]) {
            if ([icon respondsToSelector:@selector(folder)]) {
                id folder = [icon folder];
                if (folder && [folder respondsToSelector:@selector(uniqueIdentifier)]) {
                    NSString *fid = [folder uniqueIdentifier];
                    if ([fid isKindOfClass:[NSString class]] && fid.length > 0) {
                        return [@"folder:" stringByAppendingString:fid];
                    }
                }
            }
            if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
                NSString *node = [icon nodeIdentifier];
                if ([node isKindOfClass:[NSString class]] && node.length > 0) {
                    return [@"folder-node:" stringByAppendingString:node];
                }
            }
            if ([icon respondsToSelector:@selector(leafIdentifier)]) {
                NSString *leaf = [icon leafIdentifier];
                if ([leaf isKindOfClass:[NSString class]] && leaf.length > 0) {
                    return [@"folder-leaf:" stringByAppendingString:leaf];
                }
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

// 安全设置 fixed location
static void SafeSetFixedLocation(SBIconListModel *model, id icon, unsigned long long loc) {
    if (!model || !icon) return;
    @try {
        if ([model respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
            [model setFixedLocation:loc forIcon:icon options:0];
        } else if ([model respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
            [model setFixedLocation:loc forIcon:icon];
        }
    } @catch (__unused NSException *e) {}
}

// 核心：应用已记录位置；若该列表无任何记录则自动 bootstrap 当前布局
static void ApplyUserMovedLocations(SBIconListModel *model) {
    if (!model || IsDockList(model)) return;

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
            // 该列表首次出现且无记录 → 把当前所有图标位置一次性写入内存+磁盘
            NSMutableDictionary *newConfig = [NSMutableDictionary dictionaryWithCapacity:icons.count];

            for (NSUInteger i = 0; i < icons.count; i++) {
                id icon = icons[i];
                if (!icon) continue;

                NSString *iconID = GetIconID(icon);
                if (!iconID) continue;

                unsigned long long loc = i;
                @try {
                    if ([model respondsToSelector:@selector(gridCellIndexForIcon:gridCellInfoOptions:)]) {
                        unsigned long long gridLoc = [model gridCellIndexForIcon:icon gridCellInfoOptions:0];
                        if (gridLoc != NSNotFound && gridLoc < max) {
                            loc = gridLoc;
                        }
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

        // 正常热路径：只处理已记录图标（纯内存）
        NSDictionary *listConfig = nil;
        [gConfigLock lock];
        listConfig = [gGridConfig[listID] copy];
        [gConfigLock unlock];

        if (!listConfig || listConfig.count == 0) return;

        for (id icon in icons) {
            if (!icon) continue;
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
    if (!model || !icon) return;

    @try {
        if (index == NSNotFound) return;
        if (IsDockList(model)) return;

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

        // 先锁定当前移动的图标
        SafeSetFixedLocation(model, icon, index);

        // 写入内存
        LoadGridConfig();
        [gConfigLock lock];
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
        if (!listConfig) listConfig = [NSMutableDictionary dictionary];
        listConfig[iconID] = @(index);
        gGridConfig[listID] = listConfig;
        [gConfigLock unlock];

        SaveGridConfig();

        // 再把本页其他已记录图标重新锁定一次（防止拖动过程被系统清掉）
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
    // 空实现，防止系统强制重置
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
    if (!icon || IsDockList(self)) return %orig;

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
    if (!icon || IsDockList(self)) return %orig;

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

// 布局引擎热路径：优先返回已记录固定位置（纯内存）
- (unsigned long long)gridCellIndexForIcon:(id)icon gridCellInfoOptions:(unsigned long long)options {
    if (!icon || IsDockList(self)) return %orig;

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
                return loc;
            }
        }
    } @catch (__unused NSException *e) {}

    return %orig;
}

- (void)removeAllFixedIconLocations {}
- (void)removeFixedIconLocationForIcon:(id)icon {}
- (void)removeFixedIconLocationsForIcons:(id)icons {}
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
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) {
            max = [self maxNumberOfIcons];
        }
        if (index < max) return index;
    }
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) {
            max = [self maxNumberOfIcons];
        }
        if (index < max) return index;
    }
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info {
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) {
            max = [self maxNumberOfIcons];
        }
        if (index < max) return index;
    }
    return %orig;
}

// 用户真正落地的路径
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}

    id result = %orig;

    @try {
        RecordUserMovedIcon(self, icon, index);
    } @catch (__unused NSException *e) {}

    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}

    id result = %orig;

    @try {
        RecordUserMovedIcon(self, icon, index);
    } @catch (__unused NSException *e) {}

    return result;
}

// 系统内部路径
- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options {
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}

    id result = %orig;

    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}

    return result;
}

- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options {
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}

    %orig;

    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}
}

- (void)removeIcon:(id)icon {
    %orig;
    @try {
        CleanupIconFromPlist(self, icon);
    } @catch (__unused NSException *e) {}
}
- (void)removeIcon:(id)icon options:(unsigned long long)options {
    %orig;
    @try {
        CleanupIconFromPlist(self, icon);
    } @catch (__unused NSException *e) {}
}
- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    %orig;
    @try {
        CleanupIconFromPlist(self, icon);
    } @catch (__unused NSException *e) {}
}
- (void)removeIconAtIndex:(unsigned long long)index {
    id icon = nil;
    @try {
        NSArray *icons = [self icons];
        if ([icons isKindOfClass:[NSArray class]] && index < icons.count) {
            icon = icons[index];
        }
    } @catch (__unused NSException *e) {}

    %orig;

    if (icon) {
        @try {
            CleanupIconFromPlist(self, icon);
        } @catch (__unused NSException *e) {}
    }
}
- (void)removeIconAtIndex:(unsigned long long)index options:(unsigned long long)options {
    id icon = nil;
    @try {
        NSArray *icons = [self icons];
        if ([icons isKindOfClass:[NSArray class]] && index < icons.count) {
            icon = icons[index];
        }
    } @catch (__unused NSException *e) {}

    %orig;

    if (icon) {
        @try {
            CleanupIconFromPlist(self, icon);
        } @catch (__unused NSException *e) {}
    }
}

- (void)setIcons:(NSArray *)icons {
    %orig;
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options {
    id result = %orig;
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}
    return result;
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}
    return result;
}
- (id)setIconsFromIconListModel:(id)model {
    id result = %orig;
    @try {
        ApplyUserMovedLocations(self);
    } @catch (__unused NSException *e) {}
    return result;
}

%end
