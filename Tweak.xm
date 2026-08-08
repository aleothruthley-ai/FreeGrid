#import <UIKit/UIKit.h>

// ===================================================================
// 1. 头文件与方法声明
// ===================================================================
@interface SBIcon : NSObject
- (NSString *)leafIdentifier;
- (NSString *)applicationBundleIdentifier;
@end

@interface SBIconListView : UIView
- (NSString *)iconLocation;
@end

@interface SBIconListModel : NSObject
- (NSString *)uniqueIdentifier;
- (unsigned long long)maxNumberOfIcons;
@end

// ===================================================================
// 2. 自建 Plist 坐标管理引擎
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.freegrid.layout.plist"

static NSMutableDictionary *gGridConfig = nil;

// 读取自定义坐标表
static void LoadGridConfig() {
    if (!gGridConfig) {
        gGridConfig = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        if (!gGridConfig) gGridConfig = [NSMutableDictionary new];
    }
}

// 后台异步写入，保证零卡顿
static void SaveGridConfig() {
    if (gGridConfig) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [gGridConfig writeToFile:PLIST_PATH atomically:YES];
            // 给足权限防止跨进程读取失败
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0777} ofItemAtPath:PLIST_PATH error:nil];
        });
    }
}

// 提取图标唯一 ID (通杀 App 和书签)
static NSString *GetIconID(id icon) {
    if ([icon respondsToSelector:@selector(leafIdentifier)]) {
        return [icon performSelector:@selector(leafIdentifier)];
    } else if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
        return [icon performSelector:@selector(applicationBundleIdentifier)];
    }
    return [icon description];
}

// ===================================================================
// 3. 视图层：开放桌面留空权限
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
        // 核心防御：Dock 栏绝对不能留空，否则排版必定崩溃！
        if (location && [location containsString:@"Dock"]) {
            return %orig;
        }
    }
    return YES; // 桌面全面支持空隙
}

%end

// ===================================================================
// 4. 数据层：强制接管所有图标落点，彻底瘫痪自动靠拢
// ===================================================================
%hook SBIconListModel

- (BOOL)allowsFixedIconLocations {
    return YES;
}

- (long long)fixedIconLocationBehavior {
    return 1; // 强制启用系统底层的固定位置逻辑
}

// 【彻底瘫痪自动靠拢与挤压算法】
- (void)compactIcons { 
    // 留空，什么都不做，拒绝系统排版靠拢
}

// 【防御 1】：拦截读取，强制从我们的 Plist 返回坐标
- (unsigned long long)fixedLocationForIcon:(id)icon {
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    
    if (listID && iconID) {
        LoadGridConfig();
        NSDictionary *listConfig = gGridConfig[listID];
        if (listConfig && listConfig[iconID]) {
            return [listConfig[iconID] unsignedLongLongValue];
        }
    }
    return %orig;
}

// 【防御 2】：无论系统觉得放哪合适，强制回答：手指落在哪，就放哪！
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index {
    if (index != NSNotFound && index < [self maxNumberOfIcons]) {
        return index;
    }
    return %orig;
}

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    if (index != NSNotFound && index < [self maxNumberOfIcons]) {
        return index;
    }
    return %orig;
}

// 【防御 3】：屏蔽系统清空坐标的行为，守护我们的自定义布局
- (void)removeAllFixedIconLocations { }
- (void)removeFixedIconLocationsForIcons:(id)icons { }


// ===================================================================
// 5. 坐标记录打桩：操作完成后同步写入 Plist
// ===================================================================

- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    
    if (listID && iconID && index != NSNotFound) {
        LoadGridConfig();
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
        listConfig[iconID] = @(index);
        gGridConfig[listID] = listConfig;
        SaveGridConfig();
    }
    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    
    if (listID && iconID && index != NSNotFound) {
        LoadGridConfig();
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
        listConfig[iconID] = @(index);
        gGridConfig[listID] = listConfig;
        SaveGridConfig();
    }
    return result;
}

- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    %orig;
    
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    
    // 移除图标时，同步从 Plist 中删掉记录
    if (listID && iconID) {
        LoadGridConfig();
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
        if (listConfig && listConfig[iconID]) {
            [listConfig removeObjectForKey:iconID];
            gGridConfig[listID] = listConfig;
            SaveGridConfig();
        }
    }
}

%end
