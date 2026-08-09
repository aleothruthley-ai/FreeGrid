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
// 接口声明
// ===================================================================
@interface SBIcon : NSObject
- (NSString *)leafIdentifier;
- (NSString *)applicationBundleIdentifier;
- (id)nodeIdentifier;
@end

@interface SBFolderIcon : SBIcon
- (id)folder;
- (id)nodeIdentifier;
@end

@interface SBFolder : NSObject
- (NSString *)uniqueIdentifier;
- (NSString *)displayName;
@end

@interface SBIconListView : UIView
- (NSString *)iconLocation;
- (BOOL)allowsGaps;
- (BOOL)isDock;
- (id)model;
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

@interface SBIconDragManager : NSObject
- (BOOL)isIconDragging;
- (BOOL)isTrackingActiveOrDroppingIconDrags;
- (void)iconViewWillBeginDrag:(id)iconView session:(id)session;
- (void)iconDropSessionDidEnd:(id)session;
- (void)iconDropSessionDidEnd:(id)session identifier:(id)identifier draggedIconIdentifiers:(id)identifiers;
- (void)concludeIconDrop:(id)drop;
- (void)performIconDrop:(id)drop inIconListView:(id)view;
- (void)cancelAllDrags;
- (void)cancelEditingAndAllDrags;
@end

// ===================================================================
// 全局状态 & 坐标引擎
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.freegrid.layout.plist"

static NSMutableDictionary *gGridConfig = nil;
static dispatch_queue_t gSaveQueue;
static BOOL gIsDragging = NO;

static void EnsureSaveQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSaveQueue = dispatch_queue_create("com.freegrid.layout.save", DISPATCH_QUEUE_SERIAL);
    });
}

static void LoadGridConfig(void) {
    if (gGridConfig) return;
    @try {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        gGridConfig = dict ? [dict mutableCopy] : [NSMutableDictionary new];
    } @catch (__unused NSException *e) {
        gGridConfig = [NSMutableDictionary new];
    }
}

static void SaveGridConfig(void) {
    if (!gGridConfig) return;
    EnsureSaveQueue();
    NSDictionary *snapshot = [gGridConfig copy];
    dispatch_async(gSaveQueue, ^{
        @try {
            [snapshot writeToFile:PLIST_PATH atomically:YES];
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @0666}
                                             ofItemAtPath:PLIST_PATH
                                                    error:nil];
        } @catch (__unused NSException *e) {}
    });
}

// 文件夹优先用最稳定的 ID
static NSString *GetIconID(id icon) {
    if (!icon) return nil;

    Class folderIconClass = objc_getClass("SBFolderIcon");
    if (folderIconClass && [icon isKindOfClass:folderIconClass]) {
        if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
            id node = [icon nodeIdentifier];
            if ([node isKindOfClass:[NSString class]] && [(NSString *)node length] > 0) {
                return (NSString *)node;
            }
        }
        if ([icon respondsToSelector:@selector(folder)]) {
            id folder = [icon folder];
            if (folder && [folder respondsToSelector:@selector(uniqueIdentifier)]) {
                NSString *uid = [folder uniqueIdentifier];
                if (uid.length > 0) return [@"folder:" stringByAppendingString:uid];
            }
        }
    }

    if ([icon respondsToSelector:@selector(leafIdentifier)]) {
        NSString *leaf = [icon leafIdentifier];
        if (leaf.length > 0) return leaf;
    }
    if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
        NSString *bid = [icon applicationBundleIdentifier];
        if (bid.length > 0) return bid;
    }
    if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
        id node = [icon nodeIdentifier];
        if ([node isKindOfClass:[NSString class]] && [(NSString *)node length] > 0) {
            return (NSString *)node;
        }
    }
    return [NSString stringWithFormat:@"icon-%p", icon];
}

static BOOL IsDockList(SBIconListModel *model) {
    return NO;
}

// 首次安装完整快照当前布局（绝不破坏原有位置）
static void SnapshotCurrentLayoutIfNeeded(SBIconListModel *model) {
    if (!model || IsDockList(model)) return;
    NSString *listID = [model uniqueIdentifier];
    if (!listID.length) return;

    LoadGridConfig();
    if (gGridConfig[listID]) return;   // 已经有记录就绝不覆盖

    NSArray *icons = [model icons];
    if (!icons.count) return;

    NSMutableDictionary *listConfig = [NSMutableDictionary new];
    unsigned long long max = [model maxNumberOfIcons];

    for (id icon in icons) {
        NSString *iconID = GetIconID(icon);
        if (!iconID) continue;

        unsigned long long loc = NSNotFound;
        if ([model respondsToSelector:@selector(gridCellIndexForIcon:gridCellInfoOptions:)]) {
            loc = [model gridCellIndexForIcon:icon gridCellInfoOptions:0];
        }
        if (loc == NSNotFound || loc >= max) {
            loc = [model indexForIcon:icon];
        }
        if (loc != NSNotFound && loc < max) {
            listConfig[iconID] = @(loc);
            // 同步写进系统 fixed 字典
            if ([model respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
                [model setFixedLocation:loc forIcon:icon options:0];
            } else {
                [model setFixedLocation:loc forIcon:icon];
            }
        }
    }

    if (listConfig.count) {
        gGridConfig[listID] = listConfig;
        SaveGridConfig();
    }
}

// 强制把配置文件里的位置全部写回系统（防乱跑核心）
static void ApplyFixedLocationsFromPlist(SBIconListModel *model) {
    if (!model || IsDockList(model)) return;
    NSString *listID = [model uniqueIdentifier];
    if (!listID.length) return;

    LoadGridConfig();
    NSDictionary *listConfig = gGridConfig[listID];
    if (!listConfig.count) {
        SnapshotCurrentLayoutIfNeeded(model);
        return;
    }

    NSArray *icons = [model icons];
    if (!icons.count) return;

    unsigned long long max = [model maxNumberOfIcons];

    for (id icon in icons) {
        NSString *iconID = GetIconID(icon);
        if (!iconID) continue;
        NSNumber *num = listConfig[iconID];
        if (!num) continue;

        unsigned long long loc = [num unsignedLongLongValue];
        if (loc >= max) continue;

        if ([model respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
            [model setFixedLocation:loc forIcon:icon options:0];
        } else {
            [model setFixedLocation:loc forIcon:icon];
        }
    }
}

static void CleanupIconFromPlist(SBIconListModel *model, id icon) {
    if (!model || !icon) return;
    NSString *listID = [model uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (!listID || !iconID) return;

    LoadGridConfig();
    NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
    if (listConfig && listConfig[iconID]) {
        [listConfig removeObjectForKey:iconID];
        if (listConfig.count == 0) {
            [gGridConfig removeObjectForKey:listID];
        } else {
            gGridConfig[listID] = listConfig;
        }
        SaveGridConfig();
    }
}

// 松手后强制保存 + 全量拉回
static void ForceSaveFixedLocation(SBIconListModel *model, id icon, unsigned long long index) {
    if (!model || !icon || index == NSNotFound || index >= [model maxNumberOfIcons] || IsDockList(model)) return;

    NSString *listID = [model uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (!listID || !iconID) return;

    // 先写系统
    if ([model respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
        [model setFixedLocation:index forIcon:icon options:0];
    } else {
        [model setFixedLocation:index forIcon:icon];
    }

    // 再写我们的文件
    LoadGridConfig();
    NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
    listConfig[iconID] = @(index);
    gGridConfig[listID] = listConfig;
    SaveGridConfig();

    // 立刻全量拉回所有图标（解决密集页面乱跑）
    ApplyFixedLocationsFromPlist(model);
}

// ===================================================================
// 拖动状态（只在过程中放松，松手立刻收紧）
// ===================================================================
%hook SBIconDragManager

- (void)iconViewWillBeginDrag:(id)iconView session:(id)session {
    gIsDragging = YES;
    %orig;
}

- (void)iconDropSessionDidEnd:(id)session {
    gIsDragging = NO;
    %orig;
}

- (void)iconDropSessionDidEnd:(id)session identifier:(id)identifier draggedIconIdentifiers:(id)identifiers {
    gIsDragging = NO;
    %orig;
}

- (void)concludeIconDrop:(id)drop {
    gIsDragging = NO;
    %orig;
}

- (void)performIconDrop:(id)drop inIconListView:(id)view {
    %orig;
    gIsDragging = NO;
    // 松手后强制恢复我们记录的布局
    if ([view respondsToSelector:@selector(model)]) {
        id model = [view model];
        if (model) {
            ApplyFixedLocationsFromPlist(model);
            // 再保险一次，延迟一帧再拉
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ApplyFixedLocationsFromPlist(model);
            });
        }
    }
}

- (void)cancelAllDrags {
    gIsDragging = NO;
    %orig;
}

- (void)cancelEditingAndAllDrags {
    gIsDragging = NO;
    %orig;
}

%end

// ===================================================================
// 视图层
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    if ([self respondsToSelector:@selector(isDock)] && [self isDock]) return %orig;
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *loc = [self iconLocation];
        if (loc && ([loc containsString:@"Dock"] || [loc containsString:@"dock"])) return %orig;
    }
    return YES;
}

%end

// ===================================================================
// Manager
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
// 数据层（核心）
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

// 拖动中返回系统原值，松手后全部视为 fixed
- (BOOL)isIconFixed:(id)icon {
    if (!icon || IsDockList(self)) return %orig;
    if (gIsDragging) return %orig;
    return YES;
}

- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options {
    return [self isIconFixed:icon];
}

- (unsigned long long)fixedLocationForIcon:(id)icon {
    if (!icon || IsDockList(self)) return %orig;
    if (gIsDragging) return %orig;

    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (!listID || !iconID) return %orig;

    LoadGridConfig();
    NSDictionary *cfg = gGridConfig[listID];
    if (cfg && cfg[iconID]) {
        unsigned long long loc = [cfg[iconID] unsignedLongLongValue];
        if (loc < [self maxNumberOfIcons]) {
            if ([self respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
                [self setFixedLocation:loc forIcon:icon options:0];
            }
            return loc;
        }
    }

    // 没有记录就当前实际位置写进去
    unsigned long long loc = NSNotFound;
    if ([self respondsToSelector:@selector(gridCellIndexForIcon:gridCellInfoOptions:)]) {
        loc = [self gridCellIndexForIcon:icon gridCellInfoOptions:0];
    }
    if (loc == NSNotFound || loc >= [self maxNumberOfIcons]) {
        loc = [self indexForIcon:icon];
    }
    if (loc != NSNotFound && loc < [self maxNumberOfIcons]) {
        ForceSaveFixedLocation(self, icon, loc);
        return loc;
    }
    return %orig;
}

// 彻底禁用修复空隙 / 打包
- (void)removeAllFixedIconLocations {}
- (void)removeFixedIconLocationForIcon:(id)icon {}
- (void)removeFixedIconLocationsForIcons:(id)icons {}
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfo:(id)info {}
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfoOptions:(unsigned long long)options {}

- (id)_updateModelByRepairingGapsIfNecessary {
    return nil;
}
- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons {
    return nil;
}
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoiding {
    return icons;
}

- (BOOL)isGridLayoutValid { return YES; }
- (BOOL)isGridLayoutValid:(id)info { return YES; }
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options { return YES; }
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)outIcons {
    if (outIcons) *outIcons = nil;
    return YES;
}
- (BOOL)canUseFastGridLayoutValidity { return NO; }

// 拖动中让系统自己算插入点，松手后强制用我们的 index
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index {
    if (gIsDragging) return %orig;
    if (index != NSNotFound && index < [self maxNumberOfIcons]) return index;
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    if (gIsDragging) return %orig;
    if (index != NSNotFound && index < [self maxNumberOfIcons]) return index;
    return %orig;
}
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info {
    if (gIsDragging) return %orig;
    if (index != NSNotFound && index < [self maxNumberOfIcons]) return index;
    return %orig;
}

- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    if (!gIsDragging) ForceSaveFixedLocation(self, icon, index);
    return result;
}

- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options {
    id result = %orig;
    if (!gIsDragging) {
        unsigned long long gridIdx = [self fixedLocationForIcon:icon];
        if (gridIdx != NSNotFound) ForceSaveFixedLocation(self, icon, gridIdx);
    }
    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    if (!gIsDragging) ForceSaveFixedLocation(self, icon, index);
    return result;
}

- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options {
    %orig;
    if (!gIsDragging) {
        unsigned long long gridIdx = [self fixedLocationForIcon:icon];
        if (gridIdx != NSNotFound) ForceSaveFixedLocation(self, icon, gridIdx);
    }
}

- (void)removeIcon:(id)icon {
    %orig;
    CleanupIconFromPlist(self, icon);
}
- (void)removeIcon:(id)icon options:(unsigned long long)options {
    %orig;
    CleanupIconFromPlist(self, icon);
}
- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    %orig;
    CleanupIconFromPlist(self, icon);
}
- (void)removeIconAtIndex:(unsigned long long)index {
    id icon = (index < [self maxNumberOfIcons]) ? [self iconAtIndex:index] : nil;
    %orig;
    if (icon) CleanupIconFromPlist(self, icon);
}
- (void)removeIconAtIndex:(unsigned long long)index options:(unsigned long long)options {
    id icon = (index < [self maxNumberOfIcons]) ? [self iconAtIndex:index] : nil;
    %orig;
    if (icon) CleanupIconFromPlist(self, icon);
}

// 任何布局重建都强制恢复我们的位置
- (void)setIcons:(NSArray *)icons {
    %orig;
    ApplyFixedLocationsFromPlist(self);
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options {
    id result = %orig;
    ApplyFixedLocationsFromPlist(self);
    return result;
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    ApplyFixedLocationsFromPlist(self);
    return result;
}
- (id)setIconsFromIconListModel:(id)model {
    id result = %orig;
    ApplyFixedLocationsFromPlist(self);
    return result;
}

%end
