#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ===================================================================
// 结构体
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
// 接口
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

@interface SBIconView : UIView
- (id)icon;
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
// 引擎（内存优先 + 拖动全程标记）
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.iosdump.freegrid.plist"

static NSMutableDictionary *gGridConfig = nil;
static dispatch_queue_t gSaveQueue = nil;
static NSLock *gConfigLock = nil;
static BOOL gInfrastructureReady = NO;

// 用 ID 标记正在拖的图标（拖动全程有效，不只落地瞬间）
static NSString *gDraggingIconID = nil;
static NSTimeInterval gDraggingSetTime = 0;

static void EnsureInfrastructure(void) {
    if (gInfrastructureReady) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSaveQueue = dispatch_queue_create("com.iosdump.freegrid.save", DISPATCH_QUEUE_SERIAL);
        gConfigLock = [[NSLock alloc] init];
        gInfrastructureReady = YES;
    });
}

static void LoadGridConfig(void) {
    EnsureInfrastructure();
    if (gGridConfig) return;
    [gConfigLock lock];
    if (gGridConfig) { [gConfigLock unlock]; return; }
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
                                             ofItemAtPath:PLIST_PATH error:nil];
        } @catch (__unused NSException *e) {}
    });
}

static NSString *GetIconID(id icon) {
    if (!icon) return nil;
    @try {
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

static BOOL IsDockList(SBIconListModel *model) { return NO; }

static BOOL IsWidgetIcon(id icon) {
    if (!icon) return NO;
    @try {
        Class c1 = NSClassFromString(@"SBWidgetIcon");
        if (c1 && [icon isKindOfClass:c1]) return YES;
        Class c2 = NSClassFromString(@"SBHWidgetIcon");
        if (c2 && [icon isKindOfClass:c2]) return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

static void BeginDraggingIcon(id icon) {
    if (!icon) return;
    NSString *iid = GetIconID(icon);
    if (!iid) return;
    gDraggingIconID = [iid copy];
    gDraggingSetTime = CFAbsoluteTimeGetCurrent();
}

static void EndDraggingIcon(void) {
    gDraggingIconID = nil;
    gDraggingSetTime = 0;
}

static BOOL IsCurrentlyDraggingIcon(id icon) {
    if (!icon || !gDraggingIconID) return NO;
    // 超时保护：拖动标记最长 30 秒，防止异常未清理
    if (CFAbsoluteTimeGetCurrent() - gDraggingSetTime > 30.0) {
        EndDraggingIcon();
        return NO;
    }
    NSString *iid = GetIconID(icon);
    return iid && [iid isEqualToString:gDraggingIconID];
}

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
        if ([model respondsToSelector:@selector(icons)]) icons = [model icons];
        if (![icons isKindOfClass:[NSArray class]] || icons.count == 0) return;

        unsigned long long max = 0;
        if ([model respondsToSelector:@selector(maxNumberOfIcons)]) max = [model maxNumberOfIcons];
        if (max == 0) return;

        if (needBootstrap) {
            NSMutableDictionary *newConfig = [NSMutableDictionary dictionaryWithCapacity:icons.count];
            for (NSUInteger i = 0; i < icons.count; i++) {
                id icon = icons[i];
                if (!icon || IsWidgetIcon(icon)) continue;
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
            if (!icon) continue;
            if (IsCurrentlyDraggingIcon(icon)) continue; // 正在拖的不锁
            if (IsWidgetIcon(icon)) continue;
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
        if ([model respondsToSelector:@selector(uniqueIdentifier)]) listID = [model uniqueIdentifier];
        NSString *iconID = GetIconID(icon);
        if (![listID isKindOfClass:[NSString class]] || !iconID) return;
        LoadGridConfig();
        [gConfigLock lock];
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
        if (listConfig && listConfig[iconID]) {
            [listConfig removeObjectForKey:iconID];
            if (listConfig.count == 0) [gGridConfig removeObjectForKey:listID];
            else gGridConfig[listID] = listConfig;
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
        if (index == NSNotFound || IsDockList(model)) return;
        unsigned long long max = 0;
        if ([model respondsToSelector:@selector(maxNumberOfIcons)]) max = [model maxNumberOfIcons];
        if (index >= max) return;
        NSString *listID = nil;
        if ([model respondsToSelector:@selector(uniqueIdentifier)]) listID = [model uniqueIdentifier];
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

        EndDraggingIcon();
        ApplyUserMovedLocations(model);
    } @catch (__unused NSException *e) {}
}

// ===================================================================
// 视图层：拖动过程中减少 Apply，避免和系统临时布局打架
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
    // 拖动过程中不反复 Apply，减少边缘顿挫
    if (!gDraggingIconID) {
        @try {
            if ([self respondsToSelector:@selector(model)]) {
                id model = [self model];
                if (model) ApplyUserMovedLocations(model);
            }
        } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)setIconsNeedLayout {
    if (!gDraggingIconID) {
        @try {
            if ([self respondsToSelector:@selector(model)]) {
                id model = [self model];
                if (model) ApplyUserMovedLocations(model);
            }
        } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)layoutIconsIfNeeded {
    if (!gDraggingIconID) {
        @try {
            if ([self respondsToSelector:@selector(model)]) {
                id model = [self model];
                if (model) ApplyUserMovedLocations(model);
            }
        } @catch (__unused NSException *e) {}
    }
    %orig;
}

%end

// ===================================================================
// 拖动开始：在 SBIconView 层尽早标记（比 insert/move 早很多）
// ===================================================================
%hook SBIconView

// UIDragInteraction 路径（部分系统拖动会走这里）
- (void)dragInteraction:(id)interaction sessionWillBegin:(id)session {
    @try {
        if ([self respondsToSelector:@selector(icon)]) {
            BeginDraggingIcon([self icon]);
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

- (void)dragInteraction:(id)interaction session:(id)session didEndWithOperation:(unsigned long long)operation {
    %orig;
    // 不立刻清，留给 Record 清；超时保护兜底
}

// 触摸开始时也标记，覆盖 jiggle 模式拖动
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    @try {
        if ([self respondsToSelector:@selector(icon)]) {
            // 仅在可能进入拖动时预标记，真正拖动后由 mutation 路径巩固
            id icon = [self icon];
            if (icon && !IsWidgetIcon(icon)) {
                // 轻量：不在 touchesBegan 强行 Begin，避免误伤点击
            }
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

%end

// ===================================================================
// Manager
// ===================================================================
%hook SBHIconManager

- (long long)listsFixedIconLocationBehavior { return 1; }
- (long long)listsFixedIconLocationBehaviorForFolderClass:(Class)cls { return 1; }
- (long long)iconModel:(id)model listsFixedIconLocationBehaviorForFolderClass:(Class)cls { return 1; }
- (void)ensureFixedIconLocationsIfNecessary {}

%end

// ===================================================================
// 数据层
// ===================================================================
%hook SBIconListModel

- (BOOL)allowsFixedIconLocations { return YES; }
- (long long)fixedIconLocationBehavior { return 1; }
- (BOOL)requiresSomeFixedIconLocations { return YES; }

- (BOOL)isIconFixed:(id)icon {
    if (!icon || IsDockList(self)) return %orig;
    // 正在拖的图标：完全原生
    if (IsCurrentlyDraggingIcon(icon)) return NO;
    if (IsWidgetIcon(icon)) return %orig;

    @try {
        NSString *listID = nil;
        if ([self respondsToSelector:@selector(uniqueIdentifier)]) listID = [self uniqueIdentifier];
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
    if (IsCurrentlyDraggingIcon(icon)) return %orig;
    if (IsWidgetIcon(icon)) return %orig;

    @try {
        NSString *listID = nil;
        if ([self respondsToSelector:@selector(uniqueIdentifier)]) listID = [self uniqueIdentifier];
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
            if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
            if (loc < max) {
                SafeSetFixedLocation(self, icon, loc);
                return loc;
            }
        }
    } @catch (__unused NSException *e) {}
    return %orig;
}

// 热路径：正在拖的图标必须走原生，边缘才跟手
- (unsigned long long)gridCellIndexForIcon:(id)icon gridCellInfoOptions:(unsigned long long)options {
    if (!icon || IsDockList(self)) return %orig;
    if (IsCurrentlyDraggingIcon(icon)) return %orig;
    if (IsWidgetIcon(icon)) return %orig;

    @try {
        NSString *listID = nil;
        if ([self respondsToSelector:@selector(uniqueIdentifier)]) listID = [self uniqueIdentifier];
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
            if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
            if (loc < max) return loc;
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
    // 小组件 / 正在拖：完全原生
    if (IsWidgetIcon(icon) || IsCurrentlyDraggingIcon(icon)) return %orig;
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
        if (index < max) return index;
    }
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    if (IsWidgetIcon(icon) || IsCurrentlyDraggingIcon(icon)) return %orig;
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
        if (index < max) return index;
    }
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info {
    if (IsWidgetIcon(icon) || IsCurrentlyDraggingIcon(icon)) return %orig;
    if (index != NSNotFound) {
        unsigned long long max = 0;
        if ([self respondsToSelector:@selector(maxNumberOfIcons)]) max = [self maxNumberOfIcons];
        if (index < max) return index;
    }
    return %orig;
}

// 用户落地路径：一开始就标记正在拖的图标
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    BeginDraggingIcon(icon);
    if (!IsWidgetIcon(icon)) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
    id result = %orig;
    @try { RecordUserMovedIcon(self, icon, index); } @catch (__unused NSException *e) {}
    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    BeginDraggingIcon(icon);
    if (!IsWidgetIcon(icon)) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
    id result = %orig;
    @try { RecordUserMovedIcon(self, icon, index); } @catch (__unused NSException *e) {}
    return result;
}

- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options {
    BeginDraggingIcon(icon);
    if (!IsWidgetIcon(icon)) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
    id result = %orig;
    @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    EndDraggingIcon();
    return result;
}

- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options {
    BeginDraggingIcon(icon);
    if (!IsWidgetIcon(icon)) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
    %orig;
    @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    EndDraggingIcon();
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
    if (!gDraggingIconID) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options {
    id result = %orig;
    if (!gDraggingIconID) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
    return result;
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    if (!gDraggingIconID) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
    return result;
}
- (id)setIconsFromIconListModel:(id)model {
    id result = %orig;
    if (!gDraggingIconID) {
        @try { ApplyUserMovedLocations(self); } @catch (__unused NSException *e) {}
    }
    return result;
}

%end
